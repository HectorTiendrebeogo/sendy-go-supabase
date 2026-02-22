
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.0.0'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
// Use Service Role Key to bypass RLS for administrative actions like directly updating wallets/transactions
const supabaseServiceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
    // Handle CORS preflight requests
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders });
    }

    try {
        const { action, ...data } = await req.json();

        console.log(`Received action: ${action}`, data);

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

async function handlePayment(data: any) {
    const { amount, customData } = data;

    // Encode data in token so we can retrieve it in status check
    const tokenPayload = btoa(JSON.stringify({ amount, customData, type: 'payment' }));
    const transactionId = `SIM_PAY_${tokenPayload}`;

    return {
        token: transactionId,
        status: 'initiated', // Matches ligdicash-api-v2
        raw: { message: 'Payment simulation initiated' }
    };
}

async function handleDeposit(data: any) {
    const { amount, customData } = data;

    const tokenPayload = btoa(JSON.stringify({ amount, customData, type: 'deposit' }));
    const transactionId = `SIM_DEP_${tokenPayload}`;

    return {
        token: transactionId,
        status: 'initiated', // Matches ligdicash-api-v2
        raw: { message: 'Deposit simulation initiated' }
    };
}

async function handleWithdrawal(data: any) {
    const { amount, customData } = data;
    const userId = customData?.user_id;

    if (!userId) {
        throw new Error("User ID is required in customData for simulation");
    }

    // 1. Get Wallet ID and Check Balance before allowing initiation
    const { data: walletData, error: walletError } = await supabase
        .from('wallets')
        .select('id, balance')
        .eq('user_id', userId)
        .single();

    if (walletError || !walletData) {
        throw new Error("Wallet not found for user");
    }

    if (walletData.balance < amount) {
        throw new Error("Insufficient balance");
    }

    const tokenPayload = btoa(JSON.stringify({ amount, customData, type: 'withdraw' }));
    const transactionId = `SIM_WIT_${tokenPayload}`;

    return {
        token: transactionId,
        status: 'initiated', // Matches ligdicash-api-v2
        raw: { message: 'Withdrawal simulation initiated' }
    };
}

async function checkStatus(transactionId: string, type: 'deposit' | 'withdraw' | 'payment') {
    let payloadStr = transactionId;
    if (transactionId.startsWith('SIM_PAY_')) {
        payloadStr = transactionId.replace('SIM_PAY_', '');
    } else if (transactionId.startsWith('SIM_DEP_')) {
        payloadStr = transactionId.replace('SIM_DEP_', '');
    } else if (transactionId.startsWith('SIM_WIT_')) {
        payloadStr = transactionId.replace('SIM_WIT_', '');
    }

    let data;
    try {
        data = JSON.parse(atob(payloadStr));
    } catch (e) {
        console.error("Invalid simulated token", e);
        throw new Error("Invalid token");
    }

    const customData = data.customData;
    const userId = customData?.user_id;

    if (userId) {
        const payload = {
            status: 'completed', // Simulate success
            amount: data.amount,
            token: transactionId,
            operator_name: 'LigdiCash Simulation',
        };

        const txType = customData.type;

        if (txType === 'payment') {
            await handleClientPayment(supabase, payload, customData, userId);
        } else if (txType === 'wallet_topup' || txType === 'wallet_withdrawal') {
            await handleWalletTransaction(supabase, payload, customData, userId);
        }
    }

    return { status: 'completed', raw: { message: 'Simulated status check success' } };
}

// --- HELPER FUNCTIONS (Copied from ligdicash-api-v2) ---

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
            operator_name: operator_name || 'LigdiCash Simulation',
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
            operator_name: operator_name || 'LigdiCash Simulation',
            status: dbStatus,
        });
    }
}
