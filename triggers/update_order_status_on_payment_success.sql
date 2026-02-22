-- ==============================================================================
-- TRIGGER : Mise à jour du Statut de Livraison au Paiement Réussi
-- DESCRIPTION : Ce trigger s'active lorsqu'un paiement client est enregistré
--               ou mis à jour comme 'SUCCESS' dans la table `client_payments`.
--               Il met à jour le `delivery_status` de la commande associée dans la table
--               `orders` pour le passer à 'PAID'.
-- ==============================================================================

CREATE OR REPLACE FUNCTION update_order_status_on_payment_success()
RETURNS TRIGGER AS $$
BEGIN
    -- Condition : Le paiement est marqué comme réussi (SUCCESS)
    -- On met à jour le statut de la commande associée.
    UPDATE orders
    SET delivery_status = 'PAID',
        updated_at = NOW()
    WHERE id = NEW.order_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Suppression de l'ancien trigger s'il existe
DROP TRIGGER IF EXISTS trg_update_order_status_on_payment_success ON client_payments;

-- Création du trigger sur la table `client_payments`
-- Déclenchement APRES une insertion ou une mise à jour
-- UNIQUEMENT si le statut est 'SUCCESS'
CREATE TRIGGER trg_update_order_status_on_payment_success
AFTER INSERT OR UPDATE ON client_payments
FOR EACH ROW
WHEN (NEW.status = 'SUCCESS')
EXECUTE FUNCTION update_order_status_on_payment_success();
