
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.0.0";
import Ligdicash from "npm:ligdicash";

const apiKey = Deno.env.get("LIGDICASH_API_KEY")!;
const authToken = Deno.env.get("LIGDICASH_AUTH_TOKEN")!;
const platform = Deno.env.get("LIGDICASH_PLATFORM") || "live";
const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Initialize Ligdisch client
const client = new Ligdicash({
    apiKey: apiKey,
    authToken: authToken,
    platform: platform as "live" | "test"
});

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders });
    }

    try {
        const { action, ...data } = await req.json();

        if (!apiKey || !authToken) {
            throw new Error("LIGDICASH_API_KEY or LIGDICASH_AUTH_TOKEN missing.");
        }

        let result;

        switch (action) {
            case 'payment':
                result = await handlePayment(data);
                break;
            case 'deposit':
                result = await handleDeposit(data);
                break;
            case 'withdraw':
                result = await handleWithdrawal(data);
                break;
            case 'status':
                result = await checkStatus(data.token, data.type);
                break;
            default:
                throw new Error(`Unknown action: ${action}`);
        }

        return new Response(JSON.stringify(result), {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
            status: 200,
        });
    } catch (error) {
        console.error("Error processing request:", error);
        return new Response(JSON.stringify({ error: error.message }), {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
            status: 400,
        });
    }
});

async function handleDeposit(data: any) {
    const { amount, customerPhone, otp, description, customerFirstName, customerLastName, customData } = data;
    // const callbackUrl = Deno.env.get("SUPABASE_URL") + "/functions/v1/ligdicash-callback";
    const callbackUrl = "https://mhxanqvyvkffmokpmwjt.supabase.co/functions/v1/ligdicash-callback";

    console.log("Deposit Request (Ligdisch SDK):", JSON.stringify(data));

    // Create Invoice
    const invoice = client.Invoice({
        currency: "xof",
        description: description || "Recharge portefeuille SendyGo",
        customer_firstname: customerFirstName || "",
        customer_lastname: customerLastName || "",
        store_name: "SendyGo",
        store_website_url: "https://www.sendygo.com"
    });

    // Add Item
    invoice.addItem({
        name: "Recharge Portefeuille",
        description: "Crédit de compte chauffeur",
        quantity: 1,
        unit_price: amount
    });

    // Pay Without Redirection
    const response = await invoice.payWithoutRedirection({
        otp: otp,
        customer: customerPhone,
        callback_url: callbackUrl,
        custom_data: customData // { type: 'wallet_topup', ... }
    });

    console.log("Deposit Response (Ligdisch SDK):", response);

    return { token: response.token, status: 'initiated', raw: response };
}

async function handleWithdrawal(data: any) {
    const { amount, customerPhone, description, customData } = data;
    // const callbackUrl = Deno.env.get("SUPABASE_URL") + "/functions/v1/ligdicash-callback";
    const callbackUrl = "https://mhxanqvyvkffmokpmwjt.supabase.co/functions/v1/ligdicash-callback";

    console.log("Withdrawal Request (Ligdisch SDK):", JSON.stringify(data));

    const withdrawal = client.Withdrawal(
        amount,
        description || "Retrait depuis portefeuille SendyGo",
        customerPhone
    );

    // Send Withdrawal (Merchant Payout)
    const response = await withdrawal.send({
        type: "merchant", // Maps to straight/payout endpoint
        callback_url: callbackUrl,
        custom_data: customData // { type: 'wallet_withdrawal', ... }
    });

    console.log("Withdrawal Response (Ligdisch SDK):", response);

    return { token: response.token, status: 'initiated', raw: response };
}

async function handlePayment(data: any) {
    const { amount, customerPhone, otp, description, customerFirstName, customerLastName, customData } = data;
    // const callbackUrl = Deno.env.get("SUPABASE_URL") + "/functions/v1/ligdicash-callback";
    const callbackUrl = "https://mhxanqvyvkffmokpmwjt.supabase.co/functions/v1/ligdicash-callback";

    console.log("Payment Request (Ligdisch SDK):", JSON.stringify(data));

    // Create Invoice
    const invoice = client.Invoice({
        currency: "xof",
        description: description || "Paiement course SendyGo",
        customer_firstname: customerFirstName || "",
        customer_lastname: customerLastName || "",
        store_name: "SendyGo",
        store_website_url: "https://www.sendygo.com"
    });

    // Add Item
    invoice.addItem({
        name: "Paiement course",
        description: "Paiement course SendyGo",
        quantity: 1,
        unit_price: amount
    });

    // Pay Without Redirection
    const response = await invoice.payWithoutRedirection({
        otp: otp,
        customer: customerPhone,
        callback_url: callbackUrl,
        custom_data: customData // { type: 'client_payment', ... }
    });

    console.log("Payment Response (Ligdisch SDK):", response);

    return { token: response.token, status: 'initiated', raw: response };
}

async function checkStatus(token: string, type: 'deposit' | 'withdraw' | 'payment') {
    let transactionType = "";
    if (type === 'deposit' || type === 'payment') {
        transactionType = "payin";
    } else if (type === 'withdraw') {
        transactionType = "merchant_payout";
    } else {
        throw new Error("Invalid transaction type for status check. Must be 'deposit' or 'withdraw'.");
    }

    console.log(`Checking status for token: ${token}, type: ${transactionType}`);

    // FETCH TRANSACTION FROM LIGDICASH
    const transaction = await client.getTransaction(token, transactionType);
    console.log("Status Check Response (Ligdisch SDK):", transaction);

    // SYNC WITH DATABASE (Similar to Callback)
    try {
        const customData = parseCustomData(transaction.custom_data);
        const userId = customData.user_id;

        if (userId) {
            const payload = {
                status: transaction.status,
                amount: transaction.amount,
                token: token, // Transaction ID
                operator_name: transaction.operator_name || 'LigdiCash',
            };

            const txType = customData.type; // 'wallet_topup', 'wallet_withdrawal', 'payment'

            if (txType === 'payment') {
                await handleClientPayment(supabase, payload, customData, userId);
            } else if (txType === 'wallet_topup' || txType === 'wallet_withdrawal') {
                await handleWalletTransaction(supabase, payload, customData, userId);
            }
        }
    } catch (dbError) {
        console.error("Error syncing status check with DB:", dbError);
        // We continue to return the status even if DB sync fails
    }

    return { status: transaction.status, raw: transaction };
}

// --- HELPER FUNCTIONS (Copied from ligdicash-callback) ---

function parseCustomData(custom_data: any): any {
    let parsedCustomData: any = {};

    if (Array.isArray(custom_data)) {
        custom_data.forEach((item: any) => {
            if (item.keyof_customdata && item.valueof_customdata) {
                parsedCustomData[item.keyof_customdata] = item.valueof_customdata;
            } else if (item.item && item.item.keyof_customdata && item.item.valueof_customdata) {
                parsedCustomData[item.item.keyof_customdata] = item.item.valueof_customdata;
            } else {
                Object.assign(parsedCustomData, item);
            }
        });
    } else if (typeof custom_data === 'object' && custom_data !== null) {
        parsedCustomData = custom_data;
    }
    return parsedCustomData;
}

function mapLigdiCashStatus(status: string): string {
    if (status === 'completed') return 'SUCCESS';
    if (status === 'failed' || status === 'nocompleted' || status === 'cancelled') return 'FAILED';
    if (status === 'refunded') return 'REFUNDED';
    return 'PENDING';
}

async function handleClientPayment(
    supabase: SupabaseClient,
    payload: any,
    parsedCustomData: any,
    userId: string
) {
    const { status, amount, token, operator_name } = payload;
    const orderId = parsedCustomData.order_id;
    const promoCodeId = parsedCustomData.promo_code_id;
    const discountAmount = parsedCustomData.discount_amount;
    const paymentStatus = mapLigdiCashStatus(status);

    if (!orderId) return;

    const { data: existingPayment } = await supabase
        .from('client_payments')
        .select('id, status')
        .eq('transaction_id', token)
        .maybeSingle();

    if (existingPayment) {
        if (existingPayment.status === 'PENDING' && paymentStatus !== 'PENDING') {
            await supabase
                .from('client_payments')
                .update({ status: paymentStatus, updated_at: new Date() })
                .eq('id', existingPayment.id);
        }
    } else {
        await supabase.from('client_payments').insert({
            order_id: orderId,
            client_id: userId,
            amount: amount,
            discount_amount: discountAmount || 0,
            transaction_id: token,
            operator_name: operator_name || 'LigdiCash',
            promo_code_id: promoCodeId || null,
            status: paymentStatus,
            created_at: new Date(),
            updated_at: new Date()
        });
    }
}

async function handleWalletTransaction(
    supabase: SupabaseClient,
    payload: any,
    parsedCustomData: any,
    userId: string
) {
    const { status, amount, token, operator_name } = payload;
    const type = parsedCustomData.type;

    const { data: walletData } = await supabase
        .from("wallets")
        .select("id")
        .eq("user_id", userId)
        .single();

    if (!walletData) return;

    const walletId = walletData.id;
    let walletTxType;
    if (type === 'wallet_topup') walletTxType = 'CREDIT';
    else if (type === 'wallet_withdrawal') walletTxType = 'DEBIT';
    else return;

    const dbStatus = mapLigdiCashStatus(status);

    const { data: existingTx } = await supabase
        .from('wallet_transactions')
        .select('id, status')
        .eq('transaction_id', token)
        .maybeSingle();

    if (existingTx) {
        if (existingTx.status === 'PENDING' && dbStatus !== 'PENDING') {
            await supabase
                .from('wallet_transactions')
                .update({ status: dbStatus, updated_at: new Date() })
                .eq('id', existingTx.id);
        }
    } else {
        await supabase.from('wallet_transactions').insert({
            wallet_id: walletId,
            wallet_tx_type: walletTxType,
            amount: amount,
            transaction_id: token,
            operator_name: operator_name || 'LigdiCash',
            status: dbStatus,
        });
    }
}
