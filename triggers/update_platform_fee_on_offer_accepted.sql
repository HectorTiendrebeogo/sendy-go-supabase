-- ==============================================================================
-- TRIGGER : Gestion des Frais de Plateforme (Acceptation d'Offre)
-- DESCRIPTION : Ce trigger est spécifique à la gestion financière lors de l'acceptation
--               d'une offre. Il effectue deux actions principales :
--               1. Déduit la commission de la plateforme (10%) du solde du livreur.
--               2. Met à jour les soldes globaux de la plateforme (`platform_balances`).
-- ==============================================================================

CREATE OR REPLACE FUNCTION update_platform_fee_on_offer_accepted()
RETURNS TRIGGER AS $$
BEGIN
  -- Vérifie si l'offre vient d'être acceptée (passage de PENDING à ACCEPTED)
  IF NEW.offer_status = 'ACCEPTED' AND (OLD.offer_status = 'PENDING') THEN
    
    -- Initialisation de la table `platform_balances` si elle est vide (sécurité)
    IF NOT EXISTS (SELECT 1 FROM platform_balances) THEN
      INSERT INTO platform_balances (total_balance, total_platform_fee, total_promo_code_discount)
      VALUES (0, 0, 0);
    END IF;

    -- 2. Mise à jour du total des frais perçus par la plateforme
    UPDATE platform_balances
    SET total_platform_fee = total_platform_fee + (NEW.proposed_price * 0.1),
        updated_at = NOW()
    WHERE id IS NOT NULL;
    
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Suppression de l'ancien trigger s'il existe
DROP TRIGGER IF EXISTS trg_update_platform_fee_on_offer_accepted ON offers;

-- Création du trigger sur la table `offers`
CREATE TRIGGER trg_update_platform_fee_on_offer_accepted
AFTER UPDATE ON offers
FOR EACH ROW
EXECUTE FUNCTION update_platform_fee_on_offer_accepted();
