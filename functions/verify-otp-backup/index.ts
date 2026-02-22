// Edge Function: verify-otp
// Vérifie un OTP via l'API REST Ikkodi et crée/connecte l'utilisateur dans Supabase Auth

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

interface VerifyOTPRequest {
    mode: string; // LOGIN, REGISTER
    phone: string;
    countryCode: string;
    code: string;
    firstname?: string;
    lastname?: string;
    userType?: string;
    vehicleType?: string;
    vehicleRegistrationNumber?: string;
}

interface IkkodiVerifyResponse {
    status: 0 | -1;
    message: string;
}

serve(async (req) => {
    Handle CORS preflight requests
    if (req.method === "OPTIONS") {
        return new Response("ok", { headers: corsHeaders });
    }

    try {
        const {
            mode, phone, countryCode, code, firstname, lastname, userType, vehicleType, vehicleRegistrationNumber
        }: VerifyOTPRequest = await req.json();

        if (!phone || !code || !mode) {
            return new Response(
                JSON.stringify({
                    error: "Le numéro de téléphone et le code sont requis",
                }),
                {
                    status: 400,
                    headers: { ...corsHeaders, "Content-Type": "application/json" },
                }
            );
        }

        // Formater le numéro
        // Accepte: "70123456", "70 12 34 56", "+22670123456"
        const formattedPhone = phone.replace(/\s/g, "");
        const formattedCountryCode = countryCode.replace("+", "");
        const fullPhone = `${formattedCountryCode}${formattedPhone}`;

        console.log(`Vérification OTP pour: ${fullPhone}`);

        // Créer le client Supabase Admin
        const supabaseAdmin = createClient(
            Deno.env.get("SUPABASE_URL") ?? "",
            Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
        );

        // Récupérer le token OTP stocké
        const { data: verification, error: fetchError } = await supabaseAdmin
            .from("otp_verifications")
            .select("otp_token, expires_at")
            .eq("phone", formattedPhone)
            .gt("expires_at", new Date().toISOString())
            .order("created_at", { ascending: false })
            .limit(1)
            .maybeSingle();

        if (fetchError || !verification) {
            console.error("Token non trouvé ou expiré:", fetchError);
            return new Response(
                JSON.stringify({
                    error: "Code expiré ou invalide. Demandez un nouveau code.",
                }),
                {
                    status: 400,
                    headers: { ...corsHeaders, "Content-Type": "application/json" },
                }
            );
        }

        console.log("Token trouvé, vérification avec Ikkodi...");

        // Vérifier le code OTP avec Ikkodi
        const ikkodiUrl = `${IKKODI_API_BASE_URL}/${IKKODI_GROUP_ID}/otp/${IKKODI_OTP_APP_ID}/verify`;

        const ikkodiResponse = await fetch(ikkodiUrl, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "x-api-key": IKKODI_API_KEY,
            },
            body: JSON.stringify({
                identity: fullPhone,
                otp: code,
                verificationKey: verification.otp_token,
            }),
        });

        if (!ikkodiResponse.ok) {
            const errorText = await ikkodiResponse.text();
            console.error("Erreur Ikkodi:", errorText);
            return new Response(
                JSON.stringify({ error: "Code invalide" }),
                {
                    status: 400,
                    headers: { ...corsHeaders, "Content-Type": "application/json" },
                }
            );
        }

        const verifyData: IkkodiVerifyResponse = await ikkodiResponse.json();

        if (verifyData.status !== 0) {
            return new Response(
                JSON.stringify({ error: "Code invalide" }),
                {
                    status: 400,
                    headers: { ...corsHeaders, "Content-Type": "application/json" },
                }
            );
        }

        console.log("✅ OTP vérifié avec succès!");

        // Nettoyer le token utilisé
        await supabaseAdmin
            .from("otp_verifications")
            .delete()
            .eq("phone", formattedPhone);

        // Vérifier si l'utilisateur existe déjà via la table publique (qui est synchronisée via trigger)
        const { data: existingUser } = await supabaseAdmin
            .from('users')
            .select('id, is_entreprise')
            .eq('phone', fullPhone)
            .maybeSingle();

        let userId: string;
        let entrepriseCode: string | null = null;

        // Générer un mot de passe temporaire complexe pour la session
        const tempPassword = `Tp_${crypto.randomUUID()}_${Date.now()}!`;

        if (existingUser) {
            userId = existingUser.id;
            console.log("Utilisateur existant trouvé:", userId);

            // Vérifiez si l'utilisateur est une entreprise partenaire
            if (existingUser.is_entreprise === true) {
                // Récupérer le code partenaire depuis la table entreprise_codes
                const { data: entrepriseCodeData } = await supabaseAdmin
                    .from('entreprise_codes')
                    .select('code')
                    .eq('user_id', existingUser.id)
                    .maybeSingle();

                if (entrepriseCodeData) {
                    console.log("Code partenaire trouvé:", entrepriseCodeData.code);
                    entrepriseCode = entrepriseCodeData.code;
                }
            }

            // Mettre à jour le mot de passe pour permettre la connexion immédiate
            await supabaseAdmin.auth.admin.updateUserById(userId, {
                password: tempPassword
            });
        } else {
            console.log("Création d'un nouvel utilisateur...");

            console.log("Données de l'utilisateur:", {
                phone: fullPhone,
                firstname,
                lastname,
                userType,
                vehicleType,
                vehicleRegistrationNumber,
            });

            // Créer un nouveau utilisateur avec le mot de passe temporaire
            const { data: newUser, error: createError } =
                await supabaseAdmin.auth.admin.createUser({
                    phone: fullPhone,
                    password: tempPassword,
                    phone_confirm: true, // Marquer comme vérifié
                    user_metadata: {
                        first_name: firstname,
                        last_name: lastname,
                        phone: fullPhone,
                        user_type: userType,
                        vehicle_type: vehicleType || null,
                        vehicle_registration_number: vehicleRegistrationNumber || null,
                    },
                });

            if (createError) {
                console.error("Erreur création user:", createError);
                throw new Error("Erreur lors de la création de l'utilisateur");
            }

            userId = newUser.user.id;
            console.log("Nouvel utilisateur créé:", userId);
        }

        console.log("Génération de la session...");

        // Générer une session en se connectant avec le mot de passe temporaire
        const { data: signInData, error: signInError } = await supabaseAdmin.auth.signInWithPassword({
            phone: fullPhone,
            password: tempPassword
        });

        if (signInError) {
            console.error("Erreur signIn:", signInError);
            throw new Error("Erreur lors de la génération de la session");
        }

        console.log("Session générée avec succès");

        return new Response(
            JSON.stringify({
                success: true,
                access_token: signInData.session.access_token,
                refresh_token: signInData.session.refresh_token,
                user: {
                    id: userId,
                    phone: signInData?.user?.user_metadata?.phone || existingUser?.phone || null,
                    first_name: signInData?.user?.user_metadata?.first_name || existingUser?.first_name || null,
                    last_name: signInData?.user?.user_metadata?.last_name || existingUser?.last_name || null,
                    user_type: signInData?.user?.user_metadata?.user_type || existingUser?.user_type || null,
                    is_entreprise: signInData?.user?.user_metadata?.is_entreprise || existingUser?.is_entreprise || false,
                    entreprise_code: entrepriseCode || existingUser?.entreprise_code || null,
                    entreprise_name: signInData?.user?.user_metadata?.entreprise_name || existingUser?.entreprise_name || null,
                    vehicle_type: signInData?.user?.user_metadata?.vehicle_type || existingUser?.vehicle_type || null,
                    vehicle_registration_number: signInData?.user?.user_metadata?.vehicle_registration_number || existingUser?.vehicle_registration_number || null,
                    rating: signInData?.user?.user_metadata?.rating || existingUser?.rating || null,
                    default_address: signInData?.user?.user_metadata?.default_address || existingUser?.default_address || null,
                    is_verified: signInData?.user?.user_metadata?.is_verified || existingUser?.is_verified || false,
                },
            }),
            {
                status: 200,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
            }
        );
    } catch (error) {
        console.error("Erreur dans verify-otp:", error);
        return new Response(
            JSON.stringify({
                error: error.message || "Erreur lors de la vérification de l'OTP",
            }),
            {
                status: 500,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
            }
        );
    }
});
