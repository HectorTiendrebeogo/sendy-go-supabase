-- Trigger pour mettre à jour le solde bloqué du livreur en fonction des actions sur les offres

CREATE OR REPLACE FUNCTION update_driver_wallet_balance_on_offer()
RETURNS TRIGGER AS $$
DECLARE
    commission_rate DECIMAL := 0.10;
    old_commission DECIMAL;
    new_commission DECIMAL;
BEGIN
    -- Gestion de l'INSERTION (INSERT) : Augmenter le solde bloqué de 10% du prix proposé
    -- Seul le solde bloqué est manipulé, le solde réel reste inchangé.
    IF (TG_OP = 'INSERT') THEN
        UPDATE wallets
        SET 
            locked_balance = locked_balance + (NEW.proposed_price * commission_rate)
        WHERE 
            user_id = NEW.delivery_person_id;
        RETURN NEW;
    
    -- Gestion de la SUPPRESSION (DELETE) : Diminuer le solde bloqué
    -- On s'assure que l'offre n'était pas ACCEPTÉE avant de la supprimer (règle métier),
    -- mais si elle est supprimée de la BDD, on doit inverser le montant bloqué quoi qu'il arrive
    -- pour garder la cohérence.
    ELSIF (TG_OP = 'DELETE') THEN
        -- Si l'offre n'était pas ACCEPTÉE, on inverse le montant bloqué basé sur l'ANCIEN prix.
        
        IF (OLD.offer_status != 'ACCEPTED') THEN
             UPDATE wallets
            SET 
                locked_balance = locked_balance - (OLD.proposed_price * commission_rate)
            WHERE 
                user_id = OLD.delivery_person_id;
        END IF;
        
        RETURN OLD;

    -- Gestion de la MODIFICATION (UPDATE) :
    ELSIF (TG_OP = 'UPDATE') THEN
    
        -- Cas 1b : Le statut change pour ACCEPTÉ (ACCEPTED) 
        -- 1. Libérer le solde bloqué (car l'offre n'est plus "en attente")
        -- 2. Déduire le montant de la commission du solde réel du livreur
        IF (NEW.offer_status = 'ACCEPTED' AND OLD.offer_status != 'ACCEPTED') THEN
             UPDATE wallets
            SET 
                locked_balance = locked_balance - (OLD.proposed_price * commission_rate),
                balance = balance - (OLD.proposed_price * commission_rate)
            WHERE 
                user_id = NEW.delivery_person_id;

        -- Cas 1c : Le statut change pour REJETÉ (REJECTED) -> Libérer le solde bloqué uniquement
        ELSIF (NEW.offer_status = 'REJECTED' AND OLD.offer_status != 'REJECTED') THEN
             UPDATE wallets
            SET 
                locked_balance = locked_balance - (OLD.proposed_price * commission_rate)
            WHERE 
                user_id = NEW.delivery_person_id;
        
        -- Cas 2 : Le prix a changé (et le statut n'est pas rejeté ou accepté) -> Ajuster le solde bloqué
        ELSIF (NEW.proposed_price != OLD.proposed_price AND NEW.offer_status NOT IN ('REJECTED', 'ACCEPTED')) THEN
            old_commission := OLD.proposed_price * commission_rate;
            new_commission := NEW.proposed_price * commission_rate;
            
            UPDATE wallets
            SET 
                locked_balance = locked_balance - old_commission + new_commission
            WHERE 
                user_id = NEW.delivery_person_id;
        END IF;
        
        RETURN NEW;
    END IF;
    
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS update_driver_wallet_balance_on_offer_trigger ON offers;

CREATE TRIGGER update_driver_wallet_balance_on_offer_trigger
AFTER INSERT OR UPDATE OR DELETE ON offers
FOR EACH ROW
EXECUTE FUNCTION update_driver_wallet_balance_on_offer();
