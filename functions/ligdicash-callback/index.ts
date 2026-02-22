import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.0.0";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);

serve(async (req) => {
    try {
        const payload = await req.json();
        console.log("LigdiCash Callback Payload:", JSON.stringify(payload));

        const {
            custom_data,
        } = payload;

        const parsedCustomData = parseCustomData(custom_data);
        console.log("Parsed Custom Data:", JSON.stringify(parsedCustomData));

        const type = parsedCustomData.type; // 'wallet_topup', 'wallet_withdrawal', or 'payment'
        const userId = parsedCustomData.user_id;

        if (!userId) {
            console.error("User ID missing in custom_data. Cannot process transaction.");
            return new Response(JSON.stringify({ message: "User ID missing" }), { status: 200 });
        }

        if (type === 'payment') {
            return await handleClientPayment(supabase, payload, parsedCustomData, userId);
        } else if (type === 'wallet_topup' || type === 'wallet_withdrawal') {
            return await handleWalletTransaction(supabase, payload, parsedCustomData, userId);
        } else {
            console.warn("Unknown transaction type:", type);
            // Defaulting to CREDIT if undefined is risky, so we stop here.
            return new Response(JSON.stringify({ message: "Unknown transaction type" }), { status: 200 });
        }

    } catch (error) {
        console.error("Error processing callback:", error);
        return new Response(JSON.stringify({ error: error.message }), {
            headers: { "Content-Type": "application/json" },
            status: 500,
        });
    }
});

/**
 * Parses custom_data from LigdiCash callback which can be an array or object.
 */
function parseCustomData(custom_data: any): any {
    let parsedCustomData: any = {};

    if (Array.isArray(custom_data)) {
        // Convert Array format to Object format
        custom_data.forEach((item: any) => {
            // Check if item has the specific key/value structure
            if (item.keyof_customdata && item.valueof_customdata) {
                parsedCustomData[item.keyof_customdata] = item.valueof_customdata;
            }
            // Fallback: maybe it is nested in "item" property as per some docs?
            else if (item.item && item.item.keyof_customdata && item.item.valueof_customdata) {
                parsedCustomData[item.item.keyof_customdata] = item.item.valueof_customdata;
            }
            // Fallback: If it's just a key-value object inside array (unlikely but safe)
            else {
                Object.assign(parsedCustomData, item);
            }
        });
    } else if (typeof custom_data === 'object' && custom_data !== null) {
        // Already an object
        parsedCustomData = custom_data;
    }
    return parsedCustomData;
}

/**
 * Maps LigdiCash status to Application DB Status
 */
function mapLigdiCashStatus(status: string): string {
    if (status === 'completed') return 'SUCCESS';
    if (status === 'failed' || status === 'nocompleted' || status === 'cancelled') return 'FAILED';
    if (status === 'refunded') return 'REFUNDED';
    return 'PENDING';
}

/**
 * Handles Client Order Payments
 */
async function handleClientPayment(
    supabase: SupabaseClient,
    payload: any,
    parsedCustomData: any,
    userId: string
): Promise<Response> {
    const { status, amount, token, operator_name } = payload;

    console.log(`Processing Client Payment for Order: ${parsedCustomData.order_id}`);

    const orderId = parsedCustomData.order_id;
    const promoCodeId = parsedCustomData.promo_code_id;
    const discountAmount = parsedCustomData.discount_amount;
    // const customerPhone = parsedCustomData.phone; // Not currently used but available

    if (!orderId) {
        console.error("Order ID missing in custom_data for payment.");
        return new Response(JSON.stringify({ message: "Order ID missing" }), { status: 200 });
    }

    const paymentStatus = mapLigdiCashStatus(status);

    const { data: existingPayment, error: fetchError } = await supabase
        .from('client_payments')
        .select('id, status')
        .eq('transaction_id', token)
        .maybeSingle();

    if (fetchError) {
        console.error("Error fetching existing payment:", fetchError);
        throw fetchError;
    }

    if (existingPayment) {
        console.log(`Payment ${token} already processed. Current status: ${existingPayment.status}. New status: ${paymentStatus}`);

        if (existingPayment.status === 'PENDING' && paymentStatus !== 'PENDING') {
            const { error: updateError } = await supabase
                .from('client_payments')
                .update({ status: paymentStatus, updated_at: new Date() })
                .eq('id', existingPayment.id);

            if (updateError) {
                console.error("Error updating payment status:", updateError);
                throw updateError;
            }
        }
    } else {
        // Insert new payment record
        const { error: insertError } = await supabase.from('client_payments').insert({
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

        if (insertError) {
            console.error("Error inserting client payment:", insertError);
            throw insertError;
        }
    }

    return new Response(JSON.stringify({ message: "Payment processed successfully" }), {
        headers: { "Content-Type": "application/json" },
        status: 200,
    });
}

/**
 * Handles Wallet Topups and Withdrawals
 */
async function handleWalletTransaction(
    supabase: SupabaseClient,
    payload: any,
    parsedCustomData: any,
    userId: string
): Promise<Response> {
    const { status, amount, token, operator_name } = payload;
    const type = parsedCustomData.type;

    // Get Wallet ID for the user
    const { data: walletData, error: walletError } = await supabase
        .from("wallets")
        .select("id")
        .eq("user_id", userId)
        .single();

    if (walletError || !walletData) {
        console.error("Wallet not found for user: " + userId);
        return new Response(JSON.stringify({ message: "Wallet not found" }), { status: 200 });
    }

    const walletId = walletData.id;

    // Determine the transaction type for our database enum
    let walletTxType;
    if (type === 'wallet_topup') {
        walletTxType = 'CREDIT';
    } else if (type === 'wallet_withdrawal') {
        walletTxType = 'DEBIT';
    } else {
        // Should catch before calling this function, but for safety:
        return new Response(JSON.stringify({ message: "Invalid wallet transaction type" }), { status: 200 });
    }

    const dbStatus = mapLigdiCashStatus(status);

    // First check if this transaction already exists to avoid duplicates
    const { data: existingTx } = await supabase
        .from('wallet_transactions')
        .select('id, status')
        .eq('transaction_id', token)
        .maybeSingle();

    if (existingTx) {
        console.log(`Transaction ${token} already processed. Current status: ${existingTx.status}. New status: ${dbStatus}`);

        // If existing status is PENDING and new is SUCCESS/FAILED, update it.
        if (existingTx.status === 'PENDING' && dbStatus !== 'PENDING') {
            const { error: updateError } = await supabase
                .from('wallet_transactions')
                .update({ status: dbStatus, updated_at: new Date() })
                .eq('id', existingTx.id);

            if (updateError) {
                console.error("Error updating transaction status:", updateError);
                throw updateError;
            }
            console.log("Transaction status updated.");
        }

        return new Response(JSON.stringify({ message: "Transaction processed" }), { status: 200 });
    }

    // Insert new transaction
    const { error: insertError } = await supabase.from('wallet_transactions').insert({
        wallet_id: walletId,
        wallet_tx_type: walletTxType,
        amount: amount, // Ensure amount is correct type (number)
        transaction_id: token,
        operator_name: operator_name || 'LigdiCash',
        status: dbStatus,
    });

    if (insertError) {
        console.error("Error inserting transaction:", insertError);
        throw insertError;
    }

    return new Response(JSON.stringify({ message: "Callback processed successfully" }), {
        headers: { "Content-Type": "application/json" },
        status: 200,
    });
}
