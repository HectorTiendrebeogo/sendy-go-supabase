
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

console.log("Hello from process-wallet-event!");

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface WalletEventPayload {
    type: 'WALLET_CREDIT' | 'WALLET_DEBIT';
    record: any; // The wallet_transactions record
}

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders });
    }

    try {
        const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
        const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
        const supabase = createClient(supabaseUrl, supabaseServiceKey);

        const { type, record } = await req.json() as WalletEventPayload;

        if (!type || !record) {
            throw new Error("Invalid payload: missing type or record");
        }

        console.log(`Processing Wallet Event: ${type} for Transaction ID: ${record.id}`);

        // Fetch the Wallet owner (user_id)
        const walletId = record.wallet_id;
        const { data: wallet, error: walletError } = await supabase
            .from('wallets')
            .select('user_id')
            .eq('id', walletId)
            .single();

        if (walletError || !wallet) {
            throw new Error(`Wallet not found for transaction ${record.id}`);
        }

        const userId = wallet.user_id;
        const amount = record.amount;
        const operator = record.operator_name || 'SendyGo';

        // --- LOGIC PER TYPE ---

        // 1. WALLET_CREDIT -> Notify User
        if (type === 'WALLET_CREDIT') {
            await createNotification(supabase, {
                user_id: userId,
                title: 'Crédit reçu',
                body: `Votre portefeuille a été crédité de ${amount} FCFA via ${operator}.`,
                type: 'WALLET_CREDIT',
                model_id: record.id
            });
        }
        // 2. WALLET_DEBIT -> Notify User
        else if (type === 'WALLET_DEBIT') {
            await createNotification(supabase, {
                user_id: userId,
                title: 'Débit effectué',
                body: `Votre portefeuille a été débité de ${amount} FCFA pour ${operator}.`,
                type: 'WALLET_DEBIT',
                model_id: record.id
            });
        }

        return new Response(JSON.stringify({ message: `Processed ${type}` }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
        });

    } catch (error) {
        console.error(`Error in process-wallet-event:`, error);
        return new Response(JSON.stringify({ error: error.message }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 500,
        });
    }
});

async function createNotification(supabase: any, notif: any) {
    const { error } = await supabase.from('notifications').insert(notif);
    if (error) throw error;
    console.log(`Notification inserted for ${notif.type} to user ${notif.user_id}`);
}
