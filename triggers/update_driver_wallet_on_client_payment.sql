-- ==============================================================================
-- TRIGGER : Mise à jour du Wallet du Livreur après Paiement Client
-- DESCRIPTION : Ce trigger est déclenché lorsqu'un paiement client est enregistré
--               dans la table `client_payments`.
--               Il effectue les actions suivantes :
--               1. Identifie le livreur associé à la commande via l'offre acceptée.
--               2. Crédite le montant du paiement sur le solde du wallet du livreur.
-- ==============================================================================

CREATE OR REPLACE FUNCTION update_driver_wallet_on_client_payment()
RETURNS TRIGGER AS $$
DECLARE
    v_delivery_person_id UUID;
BEGIN
    -- Récupération de l'ID du livreur depuis la table des offres
    -- On cherche l'offre 'ACCEPTED' liée à la commande (order_id ici = order_id)
    SELECT delivery_person_id INTO v_delivery_person_id
    FROM offers
    WHERE order_id = NEW.order_id 
      AND offer_status = 'ACCEPTED';

    -- Sécurité : Vérification si un livreur a bien été trouvé
    IF v_delivery_person_id IS NULL THEN
        RAISE WARNING 'Aucun livreur trouvé pour la commande % (via offers)', NEW.order_id;
        RETURN NEW;
    END IF;

    -- 1. Mise à jour du solde (Crédit)
    -- Ajout du montant payé par le client au solde actuel du livreur
    UPDATE wallets
    SET balance = balance + NEW.amount,
        updated_at = NOW()
    WHERE user_id = v_delivery_person_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Suppression de l'ancien trigger s'il existe
DROP TRIGGER IF EXISTS on_client_payment_insert ON client_payments;

-- Création du trigger sur la table `client_payments`
CREATE TRIGGER on_client_payment_insert
AFTER INSERT ON client_payments
FOR EACH ROW
EXECUTE FUNCTION update_driver_wallet_on_client_payment();
