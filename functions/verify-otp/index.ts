// Edge Function: verify-otp
// Vérifie un OTP et gère l'Inscription/Connexion de manière stricte

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const IKKODI_API_KEY = Deno.env.get("IKKODI_API_KEY")!;
const IKKODI_GROUP_ID = Deno.env.get("IKKODI_GROUP_ID")!;
const IKKODI_OTP_APP_ID = Deno.env.get("IKKODI_OTP_APP_ID")!;
const IKKODI_API_BASE_URL = "https://api.ikoddi.com/api/v1/groups";

const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface VerifyOTPRequest {
    mode: string; // "LOGIN" | "REGISTER"
    phone: string;
    countryCode: string;
    code: string;
    firstname?: string;
    lastname?: string;
    userType?: string;
    vehicleType?: string;
    vehicleRegistrationNumber?: string;
}

serve(async (req) => {
    // 0. Gérer CORS preflight
    if (req.method === "OPTIONS") {
        return new Response("ok", { headers: corsHeaders });
    }

    try {
        const body: VerifyOTPRequest = await req.json();
        const { mode, phone, countryCode, code } = body;

        // Validation basique
        if (!phone || !code || !mode) {
            throw new Error("Le numéro de téléphone, le code et le mode sont requis");
        }

        // Initialisation Supabase Admin
        const supabase = createClient(
            Deno.env.get("SUPABASE_URL") ?? "",
            Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
        );

        // Formatage du numéro
        const formattedPhone = phone.replace(/\s/g, ""); // "70123456"
        const cleanCountryCode = countryCode.replace("+", ""); // "226"
        const fullPhone = `${cleanCountryCode}${formattedPhone}`; // "22670123456"

        console.log(`[Traitement] Mode: ${mode} | Phone: ${fullPhone}`);

        // --- ÉTAPE 1 : Vérifier le code OTP ---
        await verifyOTP(supabase, formattedPhone, code);

        // --- ÉTAPE 2 : Vérifier existence User ---
        const existingUser = await getUserByPhone(supabase, fullPhone);

        // --- ÉTAPE 3 : Aiguillage Strict ---
        let sessionCredentials;
        // On génère un mot de passe temporaire pour permettre la connexion (session) juste après
        const tempPassword = `Tp_${crypto.randomUUID()}_${Date.now()}!`;

        if (mode === "LOGIN") {
            if (!existingUser) {
                // Règle stricte : Login interdit si pas de compte
                return jsonResponse({ error: "Aucun compte trouvé pour ce numéro. Veuillez vous inscrire." }, 404);
            }
            sessionCredentials = await handleLogin(supabase, existingUser, tempPassword);

        } else if (mode === "REGISTER") {
            if (existingUser) {
                // Règle stricte : Inscription interdite si compte existe
                return jsonResponse({ error: "Un compte existe déjà avec ce numéro. Veuillez vous connecter." }, 409);
            }
            sessionCredentials = await handleRegister(supabase, fullPhone, body, tempPassword);

        } else {
            return jsonResponse({ error: "Mode invalide. Utilisez LOGIN ou REGISTER." }, 400);
        }

        // --- ÉTAPE 4 : Création de Session (Finale) ---
        return await createFinalSession(supabase, fullPhone, tempPassword, sessionCredentials.userData);

    } catch (error: any) {
        console.error("Erreur critique:", error);
        return jsonResponse({
            error: error.message || "Erreur interne lors de la vérification",
        }, 400);
    }
});

// ==========================================
//              SOUS-FONCTIONS
// ==========================================

// Helper pour réponse JSON rapide
function jsonResponse(data: any, status = 200) {
    return new Response(JSON.stringify(data), {
        status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
}

/**
 * Vérifie le token dans la table 'otp_verifications' et le supprime si valide.
 */
async function verifyOTP(supabase: any, phoneWithoutCountryCode: string, code: string) {
    // Check DB
    const { data: verification, error } = await supabase
        .from("otp_verifications")
        .select("otp_token, expires_at")
        .eq("phone", phoneWithoutCountryCode)
        .gt("expires_at", new Date().toISOString()) // Non expiré
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();

    if (error || !verification) {
        throw new Error("Code expiré ou invalide. Demandez un nouveau code.");
    }

    // TODO: Intégration Ikkodi possible ici si besoin via fetch

    // Suppression du token consommé (pour éviter replay)
    await supabase.from("otp_verifications").delete().eq("phone", phoneWithoutCountryCode);
    console.log("✅ OTP Validé et consommé");
}

/**
 * Récupère un utilisateur par son téléphone complet
 */
async function getUserByPhone(supabase: any, fullPhone: string) {
    const { data } = await supabase
        .from('users')
        .select('*') // On prend tout pour avoir les métadonnées existantes
        .eq('phone', fullPhone)
        .maybeSingle();
    return data;
}

/**
 * Logique de Connexion : Prépare l'utilisateur existant (Update pwd)
 */
async function handleLogin(supabase: any, user: any, tempPass: string) {
    console.log("-> Flux Login pour user:", user.id);

    // Récupération code entreprise si applicable (logique héritée)
    let finalCode = user.entreprise_code;
    if (user.is_entreprise && !finalCode) {
        const { data: codeData } = await supabase
            .from('entreprise_codes')
            .select('code')
            .eq('user_id', user.id)
            .maybeSingle();
        if (codeData) finalCode = codeData.code;
    }

    // Mise à jour mot de passe pour permettre le signIn juste après
    const { error } = await supabase.auth.admin.updateUserById(user.id, {
        password: tempPass
    });
    if (error) throw new Error("Impossible de préparer la connexion utilisateur.");

    return {
        userId: user.id,
        userData: { ...user, entreprise_code: finalCode }
    };
}

/**
 * Logique d'Inscription : Crée le nouvel utilisateur
 */
async function handleRegister(supabase: any, fullPhone: string, req: VerifyOTPRequest, tempPass: string) {
    console.log("-> Flux Register pour:", fullPhone);

    const metadata = {
        first_name: req.firstname,
        last_name: req.lastname,
        phone: fullPhone,
        user_type: req.userType,
        vehicle_type: req.vehicleType ?? null,
        vehicle_registration_number: req.vehicleRegistrationNumber ?? null,
        is_verified: false,
    };

    const { data: newUser, error } = await supabase.auth.admin.createUser({
        phone: fullPhone,
        password: tempPass,
        phone_confirm: true,
        user_metadata: metadata
    });

    if (error) throw new Error("Erreur création compte: " + error.message);

    return {
        userId: newUser.user.id,
        userData: {
            id: newUser.user.id,
            ...metadata,
            is_entreprise: false,
            rating: null,
            default_address: null
        }
    };
}

/**
 * Génère la réponse finale avec la session Supabase
 */
async function createFinalSession(supabase: any, phone: string, password: string, userData: any) {
    // Connexion effective pour avoir les tokens
    const { data, error } = await supabase.auth.signInWithPassword({
        phone: phone,
        password: password
    });

    if (error) throw new Error("Erreur génération session: " + error.message);

    console.log("✅ Session générée avec succès");

    return jsonResponse({
        success: true,
        access_token: data.session.access_token,
        refresh_token: data.session.refresh_token,
        user: userData
    });
}
