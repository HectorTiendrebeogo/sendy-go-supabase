
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

console.log("Hello from process-offer-event!");

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface OfferEventPayload {
    type: 'OFFER_CREATED' | 'OFFER_ACCEPTED' | 'OFFER_REJECTED';
    record: any; // The offer record
}

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders });
    }

    try {
        const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
        const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
        const supabase = createClient(supabaseUrl, supabaseServiceKey);

        const { type, record } = await req.json() as OfferEventPayload;

        if (!type || !record) {
            throw new Error("Invalid payload: missing type or record");
        }

        console.log(`Processing Offer Event: ${type} for Offer ID: ${record.id}`);

        // --- LOGIC PER TYPE ---

        // 1. OFFER_CREATED (New Offer) -> Notify Client
        if (type === 'OFFER_CREATED') {
            const orderId = record.order_id;

            // Fetch the order to know who is the client
            const { data: order, error } = await supabase
                .from('orders')
                .select('user_id') // Client ID
                .eq('id', orderId)
                .single();

            if (order && order.user_id) {
                await createNotification(supabase, {
                    user_id: order.user_id,
                    title: 'Nouvelle Offre !',
                    body: `Un chauffeur vous propose ${record.proposed_price} FCFA pour votre course.`,
                    type: 'OFFER_CREATED', // Using the new type
                    // model_id -> Should link to the ORDER so client can view details/offers
                    model_id: orderId
                });
            } else {
                console.warn(`Could not find order ${orderId} for offer ${record.id}`);
            }
        }
        // 2. OFFER_ACCEPTED -> Notify Driver
        else if (type === 'OFFER_ACCEPTED') {
            // The record is the offer itself, so we have delivery_person_id
            if (record.delivery_person_id) {
                await createNotification(supabase, {
                    user_id: record.delivery_person_id,
                    title: 'Offre Acceptée !',
                    body: 'Votre offre a été retenue par le client. Vous pouvez commencer la course.',
                    type: 'OFFER_ACCEPTED',
                    model_id: record.order_id // Link to order
                });
            }
        }
        // 3. OFFER_REJECTED -> Notify Driver
        else if (type === 'OFFER_REJECTED') {
            if (record.delivery_person_id) {
                await createNotification(supabase, {
                    user_id: record.delivery_person_id,
                    title: 'Offre Refusée',
                    body: 'Votre proposition de prix a été déclinée.',
                    type: 'OFFER_REJECTED',
                    model_id: record.order_id
                });
            }
        }

        return new Response(JSON.stringify({ message: `Processed ${type}` }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
        });

    } catch (error) {
        console.error(`Error in process-offer-event:`, error);
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
