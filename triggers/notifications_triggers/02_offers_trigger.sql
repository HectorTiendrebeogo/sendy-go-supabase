-- Trigger pour la table offers

-- Cette fonction déclenche l'Edge Function pour traiter les événements d'offres
-- Elle couvre : OFFER_CREATED (Nouveau), OFFER_ACCEPTED, OFFER_REJECTED
CREATE OR REPLACE FUNCTION public.handle_offer_event()
RETURNS trigger AS $$
BEGIN
  -- 1. OFFER_CREATED (Nouvelle offre de prix par un livreur)
  IF (TG_OP = 'INSERT') THEN
      PERFORM net.http_post(
          url := 'https://mhxanqvyvkffmokpmwjt.supabase.co/functions/v1/process-offer-event',
          headers := jsonb_build_object(
              'Content-Type', 'application/json',
              'Authorization', 'Bearer ' || current_setting('request.jwt.claim.role', true)
          ),
          body := jsonb_build_object(
              'type', 'OFFER_CREATED',
              'record', row_to_json(NEW)
          )
      );
  END IF;

  -- 2. Mises à jour de statut (ACCEPTED, REJECTED)
  IF (TG_OP = 'UPDATE') THEN
      -- Statut change vers ACCEPTED
      IF (NEW.offer_status = 'ACCEPTED' AND OLD.offer_status != 'ACCEPTED') THEN
          PERFORM net.http_post(
              url := 'https://mhxanqvyvkffmokpmwjt.supabase.co/functions/v1/process-offer-event',
              headers := jsonb_build_object(
                  'Content-Type', 'application/json',
                  'Authorization', 'Bearer ' || current_setting('request.jwt.claim.role', true)
              ),
              body := jsonb_build_object(
                  'type', 'OFFER_ACCEPTED',
                  'record', row_to_json(NEW)
              )
          );
      END IF;

      -- Statut change vers REJECTED
      IF (NEW.offer_status = 'REJECTED' AND OLD.offer_status != 'REJECTED') THEN
          PERFORM net.http_post(
              url := 'https://mhxanqvyvkffmokpmwjt.supabase.co/functions/v1/process-offer-event',
              headers := jsonb_build_object(
                  'Content-Type', 'application/json',
                  'Authorization', 'Bearer ' || current_setting('request.jwt.claim.role', true)
              ),
              body := jsonb_build_object(
                  'type', 'OFFER_REJECTED',
                  'record', row_to_json(NEW)
              )
          );
      END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger sur la table offers (INSERT et UPDATE)
DROP TRIGGER IF EXISTS on_offer_event ON public.offers;
CREATE TRIGGER on_offer_event
AFTER INSERT OR UPDATE ON public.offers
FOR EACH ROW
EXECUTE FUNCTION public.handle_offer_event();
