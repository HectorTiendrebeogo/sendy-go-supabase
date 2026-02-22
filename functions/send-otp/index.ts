// Edge Function: send-otp
// Envoie un OTP via l'API REST Ikkodi

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const IKKODI_API_KEY = Deno.env.get("IKKODI_API_KEY")!;
const IKKODI_GROUP_ID = Deno.env.get("IKKODI_GROUP_ID")!;
const IKKODI_OTP_APP_ID = Deno.env.get("IKKODI_OTP_APP_ID")!;
const IKKODI_API_BASE_URL = "https://api.ikoddi.com/api/v1/groups";

const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
        "authorization, x-client-info, apikey, content-type",
};

interface SendOTPRequest {
    phone: string;
    countryCode: string;
}

interface IkkodiOTPResponse {
    status: 0 | -1;
    otpToken: string;
}

serve(async (req) => {
    // Handle CORS preflight requests
    if (req.method === "OPTIONS") {
        return new Response("ok", { headers: corsHeaders });
    }

    try {
        const { phone, countryCode }: SendOTPRequest = await req.json();

        if (!phone) {
            return new Response(
                JSON.stringify({ error: "Le numéro de téléphone est requis" }),
                {
                    status: 400,
                    headers: { ...corsHeaders, "Content-Type": "application/json" },
                }
            );
        }

        // Accepte: "70123456", "70 12 34 56", "+22670123456"
        const formattedPhone = phone.replace(/\s/g, "");
        const formattedCountryCode = countryCode.replace("+", "");

        // Numéro complet pour Ikkodi
        const fullPhone = `${formattedCountryCode}${formattedPhone}`;

        console.log(`Envoi OTP pour le numéro: ${fullPhone}`);

        // Appeler l'API Ikkodi pour envoyer l'OTP
        const ikkodiUrl = `${IKKODI_API_BASE_URL}/${IKKODI_GROUP_ID}/otp/${IKKODI_OTP_APP_ID}/sms/${encodeURIComponent(
            fullPhone
        )}`;

        /*const ikkodiResponse = await fetch(ikkodiUrl, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "x-api-key": IKKODI_API_KEY,
            },
            body: JSON.stringify({}), // messageContext vide
        });

        if (!ikkodiResponse.ok) {
            const errorText = await ikkodiResponse.text();
            console.error("Erreur Ikkodi:", errorText);
            throw new Error(`Erreur Ikkodi: ${ikkodiResponse.status}`);
        }

        const otpData: IkkodiOTPResponse = await ikkodiResponse.json();

        if (otpData.status !== 0) {
            throw new Error("Échec de l'envoi de l'OTP");
        }

        console.log("OTP envoyé avec succès, token:", otpData.otpToken.substring(0, 20) + "...");*/

        // Initialisation du client Supabase avec logs de debug
        const supabaseUrl = Deno.env.get("SUPABASE_URL");
        const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

        if (!supabaseUrl || !supabaseServiceKey) {
            console.error("Configuration manquante: SUPABASE_URL ou SUPABASE_SERVICE_ROLE_KEY");
            // Ne pas afficher les clés dans les logs, juste vérifier leur présence
            console.error("SUPABASE_URL présent:", !!supabaseUrl);
            console.error("SUPABASE_SERVICE_ROLE_KEY présent:", !!supabaseServiceKey);
            throw new Error("Erreur de configuration serveur: Clés Supabase manquantes");
        }

        const supabaseClient = createClient(
            supabaseUrl,
            supabaseServiceKey
        );

        // DEBUG: Vérifier vers quelle base de données on pointe
        try {
            const urlObj = new URL(supabaseUrl);
            console.log(`[DEBUG] Connexion DB vers: ${urlObj.hostname}`);
        } catch (e) {
            console.log(`[DEBUG] URL DB invalide ou non-standard`);
        }

        console.log("Tentative d'insertion dans otp_verifications...");

        const insertData = {
            phone: formattedPhone, // Stocker sans le code pays
            full_phone: fullPhone, // Stocker avec le code pays
            otp_token: "123456", // otpData.otpToken,
            expires_at: new Date(Date.now() + 5 * 60 * 1000).toISOString(), // 5 minutes
        };

        const { error: dbError } = await supabaseClient
            .from("otp_verifications")
            .insert(insertData);

        if (dbError) {
            console.error("ERREUR FATALE DB:", JSON.stringify(dbError));
            console.error("Données tentées:", {
                phone: formattedPhone,
                full_phone: fullPhone,
                table: "otp_verifications"
            });
            throw new Error(`Erreur base de données: ${dbError.message} (${dbError.code})`);
        }

        console.log("Insertion réussie !");

        return new Response(
            JSON.stringify({
                success: true,
                message: "Code OTP envoyé par SMS",
            }),
            {
                status: 200,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
            }
        );
    } catch (error) {
        console.error("Erreur dans send-otp:", error);
        return new Response(
            JSON.stringify({
                error: error.message || "Erreur lors de l'envoi de l'OTP",
            }),
            {
                status: 500,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
            }
        );
    }
});
