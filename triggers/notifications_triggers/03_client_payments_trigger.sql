-- Trigger pour la table client_payments

-- Cette fonction déclenche l'Edge Function pour traiter les paiements clients
-- Elle couvre : PAYMENT_SUCCESS, PAYMENT_FAILED, PAYMENT_RECEIVED (dérivé de SUCCESS)
CREATE OR REPLACE FUNCTION public.handle_payment_event()
RETURNS trigger AS $$
BEGIN
  IF (TG_OP = 'INSERT') THEN
      -- PAIEMENT SUCCES
      IF (NEW.status = 'SUCCESS') THEN
          PERFORM net.http_post(
              url := 'https://mhxanqvyvkffmokpmwjt.supabase.co/functions/v1/process-payment-event',
              headers := jsonb_build_object(
                  'Content-Type', 'application/json',
                  'Authorization', 'Bearer ' || current_setting('request.jwt.claim.role', true)
              ),
              body := jsonb_build_object(
                  'type', 'PAYMENT_SUCCESS',
                  'record', row_to_json(NEW)
              )
          );
      END IF;

      -- PAIEMENT ECHEC
      IF (NEW.status = 'FAILED') THEN
           PERFORM net.http_post(
              url := 'https://mhxanqvyvkffmokpmwjt.supabase.co/functions/v1/process-payment-event',
              headers := jsonb_build_object(
                  'Content-Type', 'application/json',
                  'Authorization', 'Bearer ' || current_setting('request.jwt.claim.role', true)
              ),
              body := jsonb_build_object(
                  'type', 'PAYMENT_FAILED',
                  'record', row_to_json(NEW)
              )
          );
      END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger sur la table client_payments
DROP TRIGGER IF EXISTS on_client_payment_event ON public.client_payments;
CREATE TRIGGER on_client_payment_event
AFTER INSERT ON public.client_payments
FOR EACH ROW
EXECUTE FUNCTION public.handle_payment_event();
