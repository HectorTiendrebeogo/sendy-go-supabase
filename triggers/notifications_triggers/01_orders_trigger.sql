-- Trigger pour la table orders

-- Cette fonction déclenche l'Edge Function pour traiter les événements de commande
-- Elle couvre : CREATION, PICKED_UP, DELIVERED, CANCELLED
CREATE OR REPLACE FUNCTION public.handle_order_event()
RETURNS trigger AS $$
BEGIN
  -- 1. ORDER_CREATED (Nouvelle commande)
  IF (TG_OP = 'INSERT') THEN
      PERFORM net.http_post(
          url := 'https://mhxanqvyvkffmokpmwjt.supabase.co/functions/v1/process-order-event',
          headers := jsonb_build_object(
              'Content-Type', 'application/json',
              'Authorization', 'Bearer ' || current_setting('request.jwt.claim.role', true)
          ),
          body := jsonb_build_object(
              'type', 'ORDER_CREATED',
              'record', row_to_json(NEW)
          )
      );
  END IF;

  -- 2. Mises à jour de statut (PICKED_UP, DELIVERED, CANCELLED)
  IF (TG_OP = 'UPDATE') THEN
      -- Statut change vers PICKED_UP
      IF (NEW.delivery_progress_status = 'PICKED_UP' AND OLD.delivery_progress_status != 'PICKED_UP') THEN
          PERFORM net.http_post(
              url := 'https://mhxanqvyvkffmokpmwjt.supabase.co/functions/v1/process-order-event',
              headers := jsonb_build_object(
                  'Content-Type', 'application/json',
                  'Authorization', 'Bearer ' || current_setting('request.jwt.claim.role', true)
              ),
              body := jsonb_build_object(
                  'type', 'ORDER_PICKED_UP',
                  'record', row_to_json(NEW)
              )
          );
      END IF;

      -- Statut change vers DELIVERED
      IF (NEW.delivery_progress_status = 'DELIVERED' AND OLD.delivery_progress_status != 'DELIVERED') THEN
          PERFORM net.http_post(
              url := 'https://mhxanqvyvkffmokpmwjt.supabase.co/functions/v1/process-order-event',
              headers := jsonb_build_object(
                  'Content-Type', 'application/json',
                  'Authorization', 'Bearer ' || current_setting('request.jwt.claim.role', true)
              ),
              body := jsonb_build_object(
                  'type', 'ORDER_DELIVERED',
                  'record', row_to_json(NEW)
              )
          );
      END IF;

      -- Statut change vers CANCELLED
      IF (NEW.delivery_progress_status = 'CANCELLED' AND OLD.delivery_progress_status != 'CANCELLED') THEN
          PERFORM net.http_post(
              url := 'https://mhxanqvyvkffmokpmwjt.supabase.co/functions/v1/process-order-event',
              headers := jsonb_build_object(
                  'Content-Type', 'application/json',
                  'Authorization', 'Bearer ' || current_setting('request.jwt.claim.role', true)
              ),
              body := jsonb_build_object(
                  'type', 'ORDER_CANCELLED',
                  'record', row_to_json(NEW)
              )
          );
      END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger sur la table orders
DROP TRIGGER IF EXISTS on_order_event ON public.orders;
CREATE TRIGGER on_order_event
AFTER INSERT OR UPDATE ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.handle_order_event();
