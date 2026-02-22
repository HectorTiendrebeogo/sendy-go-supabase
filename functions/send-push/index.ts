
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { create } from "https://deno.land/x/djwt@v2.4/mod.ts";

console.log("Hello from send-push!");

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Input payload from 'notifications' trigger
interface NotificationPayload {
    user_id: string; // The user to notify
    title: string;
    body: string;
    data?: Record<string, string>; // { type: 'ORDER_CREATED', model_id: '...' }
}

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders });
    }

    try {
        const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
        const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
        const supabase = createClient(supabaseUrl, supabaseServiceKey);

        const payload = await req.json() as NotificationPayload;
        if (!payload.user_id || !payload.title || !payload.body) {
            throw new Error("Missing required fields: user_id, title, or body.");
        }

        console.log(`Sending Push: ${payload.title} to User: ${payload.user_id}`);

        // 1. Retrieve User's FCM Token from 'auth.users' metadata
        const { data: userData, error: userError } = await supabase.auth.admin.getUserById(
            payload.user_id
        );

        const fcmToken = userData?.user?.user_metadata?.fcm_token;

        if (userError || !fcmToken) {
            console.warn(`No FCM token found for user ${payload.user_id}. Notification logged but not pushed.`);
            // We return 200 because the function executed correctly, just no device to reach.
            return new Response(JSON.stringify({ message: "No FCM token, skipped push." }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                status: 200,
            });
        }

        // 2. Authenticate with Firebase (Service Account)
        const serviceAccountStr = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
        if (!serviceAccountStr) {
            throw new Error("Missing FIREBASE_SERVICE_ACCOUNT secret.");
        }
        const serviceAccount = JSON.parse(serviceAccountStr);
        const accessToken = await getAccessToken(serviceAccount);

        // 3. Send to FCM (HTTP v1 API)
        const projectId = serviceAccount.project_id;
        const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

        const messagePayload = {
            message: {
                token: fcmToken,
                notification: {
                    title: payload.title,
                    body: payload.body,
                },
                data: payload.data || {},
                // Configurations spécifiques à Android pour la priorité en arrière-plan (Doze mode bypass)
                android: {
                    priority: 'high', // La documentation FCM HTTP v1 exige la casse 'high' ou 'normal'
                    notification: {
                        default_sound: true,
                        default_vibrate_timings: true,
                        notification_priority: 'PRIORITY_MAX'
                    }
                },
                // Optional: APNs (iOS)
                apns: {
                    payload: {
                        aps: {
                            contentAvailable: true,
                        }
                    }
                }
            }
        };

        const fcmResponse = await fetch(url, {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${accessToken}`,
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(messagePayload),
        });

        if (!fcmResponse.ok) {
            const errorText = await fcmResponse.text();
            console.error("FCM Error Response:", errorText);
            throw new Error(`Error sending to FCM: ${fcmResponse.status}`);
        }

        const responseData = await fcmResponse.json();
        console.log("Successfully pushed to FCM:", responseData);

        return new Response(JSON.stringify(responseData), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 200,
        });

    } catch (error) {
        console.error("Error in send-push:", error);
        return new Response(JSON.stringify({ error: error.message }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 500,
        });
    }
});

// OAuth2 Token generation for Firebase
async function getAccessToken(serviceAccount: any): Promise<string> {
    const SCOPES = ["https://www.googleapis.com/auth/firebase.messaging"];
    const header = { alg: "RS256", typ: "JWT" };
    const now = Math.floor(Date.now() / 1000);
    const claimSet = {
        iss: serviceAccount.client_email,
        scope: SCOPES.join(" "),
        aud: "https://oauth2.googleapis.com/token",
        exp: now + 3600,
        iat: now,
    };

    const privateKey = serviceAccount.private_key.replace(/\\n/g, "\n");
    const key = await crypto.subtle.importKey(
        "pkcs8",
        pemToArrayBuffer(privateKey),
        { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
        false,
        ["sign"]
    );

    const jwt = await create(header as any, claimSet, key);

    const params = new URLSearchParams();
    params.append("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer");
    params.append("assertion", jwt);

    const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: params,
    });

    if (!tokenResponse.ok) {
        throw new Error(`Failed to get access token: ${await tokenResponse.text()}`);
    }

    const tokenData = await tokenResponse.json();
    return tokenData.access_token;
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
    const b64Lines = pem.replace(/-----BEGIN PRIVATE KEY-----/, "").replace(/-----END PRIVATE KEY-----/, "").replace(/\n/g, "");
    const b64 = atob(b64Lines);
    const buf = new ArrayBuffer(b64.length);
    const view = new Uint8Array(buf);
    for (let i = 0; i < b64.length; i++) {
        view[i] = b64.charCodeAt(i);
    }
    return buf;
}
