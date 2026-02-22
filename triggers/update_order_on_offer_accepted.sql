-- ==============================================================================
-- TRIGGER : Mise à jour de la Commande lors de l'Acceptation d'une Offre
-- DESCRIPTION : Ce trigger s'active lorsqu'une offre passe au statut 'ACCEPTED'.
--               Il effectue les opérations suivantes :
--               1. Met à jour la commande concernée (`orders`) avec :
--                  - Le prix final (delivery_price)
--                  - La commission (delivery_fee)
--                  - Le statut de la commande ('PRICE_ACCEPTED')
--                  - Le statut de progression ('PENDING')
--               2. Rejette automatiquement toutes les autres offres en attente ('PENDING')
--                  pour cette même commande, afin d'éviter les conflits.
-- ==============================================================================

CREATE OR REPLACE FUNCTION update_order_on_offer_accepted()
RETURNS TRIGGER AS $$
BEGIN
  -- Condition : L'offre vient d'être acceptée (statut PENDING -> ACCEPTED)
  IF NEW.offer_status = 'ACCEPTED' AND (OLD.offer_status = 'PENDING') THEN
    
    -- 1. Mise à jour des informations de la commande
    UPDATE orders
    SET 
      delivery_price = NEW.proposed_price,
      delivery_fee = NEW.proposed_price * 0.1, -- Calcul de la commission (10%)
      delivery_status = 'PRICE_ACCEPTED',
      delivery_progress_status = 'PENDING',
      updated_at = NOW()
    WHERE id = NEW.order_id;

    -- 2. Annulation automatique des offres concurrentes
    -- Toutes les autres offres 'PENDING' pour cette commande passent à 'REJECTED'
    UPDATE offers
    SET offer_status = 'REJECTED'
    WHERE order_id = NEW.order_id
      AND id != NEW.id
      AND offer_status = 'PENDING';
      
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Suppression de l'ancien trigger s'il existe pour éviter les doublons
DROP TRIGGER IF EXISTS trg_update_order_on_offer_accepted ON offers;

-- Création du trigger sur la table `offers`
-- Déclenché après chaque mise à jour d'une ligne
CREATE TRIGGER trg_update_order_on_offer_accepted
AFTER UPDATE ON offers
FOR EACH ROW
EXECUTE FUNCTION update_order_on_offer_accepted();
