-- ==============================================================================
-- TRIGGER : Gestion des Codes Promo et Statistiques Financières
-- DESCRIPTION : Ce trigger est déclenché lors de l'enregistrement d'un paiement client.
--               Si un code promo a été utilisé :
--               1. Incrémente le compteur d'utilisation du code promo.
--               2. Ajuste les balances de la plateforme :
--                  - Réduit les frais de plateforme perçus (car le client a payé moins).
--                  - Augmente le total des remises accordées.
-- ==============================================================================

CREATE OR REPLACE FUNCTION update_promo_stats_on_client_payment()
RETURNS TRIGGER AS $$
DECLARE
    v_discount_amount NUMERIC(10,2);
BEGIN
    -- Vérification si un code promo est présent dans le paiement
    IF NEW.promo_code_id IS NOT NULL THEN
        
        -- Initialisation de la table `platform_balances` si nécessaire
        IF NOT EXISTS (SELECT 1 FROM platform_balances) THEN
            INSERT INTO platform_balances (total_balance, total_platform_fee, total_promo_code_discount)
            VALUES (0, 0, 0);
        END IF;

        -- 1. Incrémentation du compteur d'utilisation du code promo
        UPDATE promo_codes
        SET total_uses = total_uses + 1,
            updated_at = NOW()
        WHERE id = NEW.promo_code_id;

        -- Récupération du montant de la réduction appliquée
        v_discount_amount := COALESCE(NEW.discount_amount, 0);

        -- 2. Mise à jour des balances financières de la plateforme
        -- On déduit la remise des frais de plateforme et on l'ajoute au total des remises
        UPDATE platform_balances
        SET total_platform_fee = total_platform_fee - v_discount_amount,
            total_promo_code_discount = total_promo_code_discount + v_discount_amount,
            updated_at = NOW()
        WHERE id IS NOT NULL;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Suppression de l'ancien trigger s'il existe
DROP TRIGGER IF EXISTS trg_update_promo_stats_on_client_payment ON client_payments;

-- Création du trigger sur la table `client_payments`
CREATE TRIGGER trg_update_promo_stats_on_client_payment
AFTER INSERT ON client_payments
FOR EACH ROW
EXECUTE FUNCTION update_promo_stats_on_client_payment();
