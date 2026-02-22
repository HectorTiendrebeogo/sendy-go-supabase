-- Trigger pour la table wallet_transactions

-- Cette fonction déclenche l'Edge Function pour traiter les événements de portefeuille
-- Elle couvre : WALLET_CREDIT, WALLET_DEBIT
CREATE OR REPLACE FUNCTION public.handle_wallet_event()
RETURNS trigger AS $$
BEGIN
  -- Seule l'insertion nous intéresse pour l'historique
  IF (TG_OP = 'INSERT') THEN
      -- CREDIT
      IF (NEW.wallet_tx_type = 'CREDIT') THEN
          PERFORM net.http_post(
              url := 'https://mhxanqvyvkffmokpmwjt.supabase.co/functions/v1/process-wallet-event',
              headers := jsonb_build_object(
                  'Content-Type', 'application/json',
                  'Authorization', 'Bearer ' || current_setting('request.jwt.claim.role', true)
              ),
              body := jsonb_build_object(
                  'type', 'WALLET_CREDIT',
                  'record', row_to_json(NEW)
              )
          );
      END IF;

      -- DEBIT
      IF (NEW.wallet_tx_type = 'DEBIT') THEN
           PERFORM net.http_post(
              url := 'https://mhxanqvyvkffmokpmwjt.supabase.co/functions/v1/process-wallet-event',
              headers := jsonb_build_object(
                  'Content-Type', 'application/json',
                  'Authorization', 'Bearer ' || current_setting('request.jwt.claim.role', true)
              ),
              body := jsonb_build_object(
                  'type', 'WALLET_DEBIT',
                  'record', row_to_json(NEW)
              )
          );
      END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger sur la table wallet_transactions
DROP TRIGGER IF EXISTS on_wallet_event ON public.wallet_transactions;
CREATE TRIGGER on_wallet_event
AFTER INSERT ON public.wallet_transactions
FOR EACH ROW
EXECUTE FUNCTION public.handle_wallet_event();
