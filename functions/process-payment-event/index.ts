
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

console.log("Hello from process-payment-event!");

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface PaymentEventPayload {
    type: 'PAYMENT_SUCCESS' | 'PAYMENT_FAILED';
    record: any; // The payment record from client_payments
}

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders });
    }

    try {
        const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
        const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
        const supabase = createClient(supabaseUrl, supabaseServiceKey);

        const { type, record } = await req.json() as PaymentEventPayload;

        if (!type || !record) {
            throw new Error("Invalid payload: missing type or record");
        }

        console.log(`Processing Payment Event: ${type} for Payment ID: ${record.id}`);

        // --- LOGIC PER TYPE ---

        // 1. PAYMENT_SUCCESS -> Notify Client AND Driver
        if (type === 'PAYMENT_SUCCESS') {
            // A. Notify Client (Confirmation)
            await createNotification(supabase, {
                user_id: record.client_id, // Schema confirms 'client_id'
                title: 'Paiement Confirmé',
                body: `Votre paiement de ${record.amount} FCFA a bien été pris en compte.`,
                type: 'PAYMENT_SUCCESS',
                model_id: record.id
            });

            // B. Notify Driver (PAYMENT_RECEIVED logic)
            // Find the driver associated with the order
            const { data: acceptedOffer, error } = await supabase
                .from('offers')
                .select('delivery_person_id')
                .eq('order_id', record.order_id)
                .eq('offer_status', 'ACCEPTED')
                .maybeSingle();

            if (acceptedOffer && acceptedOffer.delivery_person_id) {
                await createNotification(supabase, {
                    user_id: acceptedOffer.delivery_person_id,
                    title: 'Paiement Reçu !',
                    body: 'Le paiement de la course a été effectué par le client.',
                    type: 'PAYMENT_RECEIVED', // Using the specific type for driver
                    model_id: record.id // Or record.order_id? Probably payment ID.
                });
            }
        }
        // 2. PAYMENT_FAILED -> Notify Client
        else if (type === 'PAYMENT_FAILED') {
            const userId = record.client_id || record.user_id; // Check schema
            if (userId) {
                await createNotification(supabase, {
                    user_id: userId,
                    title: 'Échec du Paiement',
                    body: 'La transaction n\'a pas pu aboutir. Veuillez réessayer.',
                    type: 'PAYMENT_FAILED',
                    model_id: record.id
                });
            }
        }

        return new Response(JSON.stringify({ message: `Processed ${type}` }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
        });

    } catch (error) {
        console.error(`Error in process-payment-event:`, error);
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
