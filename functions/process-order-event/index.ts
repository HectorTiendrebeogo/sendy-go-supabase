
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

console.log("Hello from process-order-event!");

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Haversine formula to calculate distance in km
function calculateDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
    if (!lat1 || !lon1 || !lat2 || !lon2) return 99999;

    const R = 6371; // Radius of the earth in km
    const dLat = deg2rad(lat2 - lat1);
    const dLon = deg2rad(lon2 - lon1);
    const a =
        Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(deg2rad(lat1)) * Math.cos(deg2rad(lat2)) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    const d = R * c; // Distance in km
    return d;
}

function deg2rad(deg: number): number {
    return deg * (Math.PI / 180);
}

interface OrderEventPayload {
    type: 'ORDER_CREATED' | 'ORDER_PICKED_UP' | 'ORDER_DELIVERED' | 'ORDER_CANCELLED';
    record: any; // The order record
}

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders });
    }

    try {
        const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
        const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
        const supabase = createClient(supabaseUrl, supabaseServiceKey);

        const { type, record } = await req.json() as OrderEventPayload;

        if (!type || !record) {
            throw new Error("Invalid payload: missing type or record");
        }

        console.log(`Processing Order Event: ${type} for Order ID: ${record.id}`);

        // --- LOGIC PER TYPE ---

        // 1. ORDER_CREATED -> Notify Drivers
        if (type === 'ORDER_CREATED') {
            await handleOrderCreated(supabase, record);
        }
        // 2. ORDER_PICKED_UP -> Notify Client
        else if (type === 'ORDER_PICKED_UP') {
            await createNotification(supabase, {
                user_id: record.user_id, // Client ID
                title: 'Colis Ramassé',
                body: 'Le livreur a récupéré votre colis.',
                type: 'ORDER_PICKED_UP',
                model_id: record.id
            });
        }
        // 3. ORDER_DELIVERED -> Notify Client
        else if (type === 'ORDER_DELIVERED') {
            await createNotification(supabase, {
                user_id: record.user_id, // Client ID
                title: 'Colis Livré !',
                body: 'Votre colis a bien été livré.',
                type: 'ORDER_DELIVERED',
                model_id: record.id
            });
        }
        // 4. ORDER_CANCELLED -> Notify Driver (only if one was assigned)
        else if (type === 'ORDER_CANCELLED') {
            // Since there is no 'delivery_person_id' in orders table, we must find the accepted offer
            const { data: acceptedOffer, error: offerError } = await supabase
                .from('offers')
                .select('delivery_person_id')
                .eq('order_id', record.id)
                .eq('offer_status', 'ACCEPTED')
                .maybeSingle();

            if (offerError) {
                console.error("Error finding accepted offer for cancelled order default (PGRST check):", offerError);
            }

            if (acceptedOffer && acceptedOffer.delivery_person_id) {
                await createNotification(supabase, {
                    user_id: acceptedOffer.delivery_person_id,
                    title: 'Course Annulée',
                    body: 'La course en cours a été annulée.',
                    type: 'ORDER_CANCELLED',
                    model_id: record.id
                });
            }
        }

        return new Response(JSON.stringify({ message: `Processed ${type}` }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
        });

    } catch (error) {
        console.error(`Error in process-order-event:`, error);
        return new Response(JSON.stringify({ error: error.message }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 500,
        });
    }
});

// --- HELPER FUNCTIONS ---

async function handleOrderCreated(supabase: any, order: any) {
    const orderLat = order.pickup_latitude;
    const orderLon = order.pickup_longitude;

    if (!orderLat || !orderLon) {
        console.warn("Order has no pickup coordinates, skipping driver notification.");
        return;
    }

    // 1. Fetch ACTIVE Drivers & Back Route via RPC
    const { data: drivers, error } = await supabase.rpc('get_active_drivers_with_back_route');

    if (error) throw error;
    if (!drivers || drivers.length === 0) return;

    const driversToNotify: string[] = [];
    const driverIds = drivers.map((d: any) => d.id);

    // 2. Fetch Helper Data
    // A. Driver Addresses
    const { data: addresses } = await supabase
        .from('driver_addresses')
        .select('driver_id, latitude, longitude')
        .in('driver_id', driverIds);

    for (const driver of drivers) {
        let isMatch = false;

        // A. Check Back Route (Priority)
        if (driver.back_route) {
            try {
                const route = typeof driver.back_route === 'string' ? JSON.parse(driver.back_route) : driver.back_route;

                // Structure: { "start": { "lat": ..., "lng": ... }, "end": { ... } }
                const lat = route?.start?.lat;
                const lng = route?.start?.lng;

                if (lat && lng) {
                    const dist = calculateDistance(orderLat, orderLon, parseFloat(lat), parseFloat(lng));
                    if (dist <= 1.0) {
                        isMatch = true;
                    }
                }
            } catch (e) {
                console.warn(`Error parsing back_route for driver ${driver.id}:`, e);
            }
        }

        // B. Check Saved Addresses (If not already matched)
        if (!isMatch) {
            // Find addresses for this driver
            const driverAddrs = addresses?.filter((a: any) => a.driver_id === driver.id) || [];
            for (const addr of driverAddrs) {
                const dist = calculateDistance(orderLat, orderLon, addr.latitude, addr.longitude);
                if (dist <= 1.0) {
                    isMatch = true;
                    break;
                }
            }
        }

        if (isMatch) {
            driversToNotify.push(driver.id);
        }
    }

    console.log(`ORDER_CREATED: Notifying ${driversToNotify.length} drivers.`);

    // 3. Insert Notifications
    if (driversToNotify.length > 0) {
        // Bulk insert
        const payload = driversToNotify.map(driverId => ({
            user_id: driverId,
            title: 'Nouvelle course disponible !',
            body: 'Une commande est disponible près de votre position.',
            type: 'ORDER_CREATED',
            model_id: order.id,
            // is_read defaults to false
        }));

        const { error: insertError } = await supabase.from('notifications').insert(payload);
        if (insertError) console.error("Error inserting notifications:", insertError);
    }
}

async function createNotification(supabase: any, notif: any) {
    const { error } = await supabase.from('notifications').insert(notif);
    if (error) throw error;
    console.log(`Notification inserted for ${notif.type} to user ${notif.user_id}`);
}
