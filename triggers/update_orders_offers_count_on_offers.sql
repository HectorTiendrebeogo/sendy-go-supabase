-- ==============================================================================
-- TRIGGER : Compteur d'Offres (Offers Count)
-- DESCRIPTION : Ce trigger maintient à jour la colonne `offers_count` dans la table `orders`.
--               Il s'exécute à chaque fois qu'une offre est ajoutée ou supprimée.
--               - INSERT : Incrémente le compteur (+1).
--               - DELETE : Décrémente le compteur (-1).
--               Cela permet d'avoir le nombre d'offres en temps réel sans faire de count(*) coûteux.
-- ==============================================================================

DROP TRIGGER IF EXISTS on_offer_change ON offers;

-- FONCTION : Met à jour le compteur d'offres dans la table orders
CREATE OR REPLACE FUNCTION update_orders_offers_count()
RETURNS TRIGGER AS $$
BEGIN
  -- Cas d'une insertion (nouvelle offre)
  IF (TG_OP = 'INSERT') THEN
    UPDATE orders
    SET offers_count = COALESCE(offers_count, 0) + 1
    WHERE id = NEW.order_id;
    RETURN NEW;
  
  -- Cas d'une suppression (offre retirée)
  ELSIF (TG_OP = 'DELETE') THEN
    UPDATE orders
    SET offers_count = GREATEST(0, COALESCE(offers_count, 0) - 1)
    WHERE id = OLD.order_id;
    RETURN OLD;
  END IF;
  
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- TRIGGER : Déclenchement sur INSERT ou DELETE
CREATE TRIGGER on_offer_change
AFTER INSERT OR DELETE ON offers
FOR EACH ROW
EXECUTE FUNCTION update_orders_offers_count();