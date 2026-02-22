
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const LIGDICASH_PAYIN_STRAIGHT_URL = "https://app.ligdicash.com/pay/v01/straight/checkout-invoice/create";
const LIGDICASH_PAYOUT_STRAIGHT_URL = "https://app.ligdicash.com/pay/v01/straight/payout";

const apiKey = Deno.env.get("LIGDICASH_API_KEY")!;
const authToken = Deno.env.get("LIGDICASH_AUTH_TOKEN")!;

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders });
    }

    try {
        const { action, ...data } = await req.json();

        if (!apiKey || !authToken) {
            throw new Error("LIGDICASH_API_KEY or LIGDICASH_AUTH_TOKEN missing.");
        }

        let result;

        switch (action) {
            case 'deposit':
                result = await handleDepositStraight(data);
                break;
            case 'withdraw':
                result = await handleWithdrawalStraight(data);
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

async function handleDepositStraight(data: any) {
    const { amount, customerPhone, otp, description, customerFirstName, customerLastName, customerEmail, customData } = data;
    // const callbackUrl = Deno.env.get("SUPABASE_URL") + "/functions/v1/ligdicash-callback";
    const callbackUrl = "https://mhxanqvyvkffmokpmwjt.supabase.co/functions/v1/ligdicash-callback";

    // Structure "commande" pour l'endpoint /straight/checkout-invoice/create
    const payload = {
        commande: {
            invoice: {
                items: [
                    {
                        name: 'Recharge Portefeuille',
                        description: 'Crédit de compte chauffeur',
                        quantity: 1,
                        unit_price: amount,
                        total_price: amount
                    }
                ],
                total_amount: amount,
                devise: 'XOF',
                description: description || "Recharge portefeuille SendyGo",
                customer: customerPhone,
                customer_firstname: customerFirstName || '',
                customer_lastname: customerLastName || '',
                customer_email: customerEmail || '',
                external_id: "",
                otp: otp
            },
            store: {
                name: 'SendyGo',
                website_url: 'https://www.sendygo.com'
            },
            actions: {
                cancel_url: "",
                return_url: "",
                callback_url: callbackUrl
            },
            custom_data: customData // { type: 'wallet_topup', ... }
        }
    };

    console.log("Deposit Payload (Straight) to LigdiCash:", JSON.stringify(payload));

    const response = await fetch(LIGDICASH_PAYIN_STRAIGHT_URL, {
        method: "POST",
        headers: {
            "Authorization": `Bearer ${authToken}`,
            "Apikey": apiKey,
            "Accept": "application/json",
            "Content-Type": "application/json"
        },
        body: JSON.stringify(payload)
    });

    console.log("Deposit Response (Straight) from LigdiCash:", response);

    if (!response.ok) {
        const err = await response.text();
        console.error("LigdiCash Error Response:", err);
        try {
            const errJson = JSON.parse(err);
            throw new Error(errJson.message || `Ligdicash Payin Error: ${err}`);
        } catch (_) {
            throw new Error(`Ligdicash Payin Error: ${err}`);
        }
    }

    const responseData = await response.json();
    return { token: responseData.token, status: 'initiated', raw: responseData };
}

async function handleWithdrawalStraight(data: any) {
    const { amount, customerPhone, description, customData } = data;
    // const callbackUrl = Deno.env.get("SUPABASE_URL") + "/functions/v1/ligdicash-callback";
    const callbackUrl = "https://mhxanqvyvkffmokpmwjt.supabase.co/functions/v1/ligdicash-callback";

    // Structure for Straight Payout
    const payload = {
        commande: {
            amount: amount,
            description: description || "Retrait depuis portefeuille SendyGo",
            customer: customerPhone,
            custom_data: customData, // { type: 'wallet_withdrawal', ... }
            callback_url: callbackUrl
        }
    };

    console.log("Withdrawal Payload (Straight) to LigdiCash:", JSON.stringify(payload));

    const response = await fetch(LIGDICASH_PAYOUT_STRAIGHT_URL, {
        method: "POST",
        headers: {
            "Authorization": `Bearer ${authToken}`,
            "Apikey": apiKey,
            "Accept": "application/json",
            "Content-Type": "application/json"
        },
        body: JSON.stringify(payload)
    });

    if (!response.ok) {
        const err = await response.text();
        console.error("LigdiCash Withdrawal Error Response:", err);
        try {
            const errJson = JSON.parse(err);
            throw new Error(errJson.message || `Ligdicash Withdrawal Error: ${err}`);
        } catch (_) {
            throw new Error(`Ligdicash Withdrawal Error: ${err}`);
        }
    }

    const responseData = await response.json();
    return { token: responseData.token, status: 'initiated', raw: responseData };
}

async function checkStatus(token: string, type: 'deposit' | 'withdraw') {
    if (type === 'deposit') {
        const statusUrl = `https://app.ligdicash.com/pay/v01/redirect/checkout-invoice/confirm/?invoiceToken=${token}`;
        const res = await fetch(statusUrl, {
            method: "GET",
            headers: {
                "Authorization": `Bearer ${authToken}`,
                "Apikey": apiKey,
                "Accept": "application/json"
            }
        });

        if (res.ok) {
            const data = await res.json();
            return { status: data.status, raw: data };
        } else {
            // Handle 404 or other errors
            const errorText = await res.text();
            console.error("Payin Check Error:", errorText);
            // Instead of throwing immediately, we can return status 'unknown' or 'failed' if 404
            if (res.status === 404) return { status: 'not_found' };
            throw new Error(`Failed to check deposit status: ${errorText}`);
        }
    } else if (type === 'withdraw') {
        const payoutUrl = `https://app.ligdicash.com/pay/v01/straight/payout/confirm/?payoutToken=${token}`;
        const res = await fetch(payoutUrl, {
            headers: { "Authorization": `Bearer ${authToken}`, "Apikey": apiKey, "Accept": "application/json" }
        });
        if (res.ok) {
            const data = await res.json();
            return { status: data.status, raw: data };
        } else {
            const errorText = await res.text();
            console.error("Payout Check Error:", errorText);
            if (res.status === 404) return { status: 'not_found' };
            throw new Error(`Failed to check withdrawal status: ${errorText}`);
        }
    } else {
        // Fallback or Error if type is missing/unknown
        // Pour contrer les erreurs si le client flutter n'a pas encore ete deployé:
        // on peut tenter le fallback de deviner. Mais mieux vaut une erreur explicite pour forcer la maj.
        throw new Error("Invalid transaction type for status check. Must be 'deposit' or 'withdraw'.");
    }
}
