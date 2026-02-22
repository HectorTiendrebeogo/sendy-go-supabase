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
-- Trigger final pour la table notifications

-- Ce trigger se déclenche APRÈS une insertion dans la table notifications.
-- Il est responsable de l'envoi réel du Push Notification via l'Edge Function 'send-push'.
-- Les triggers précédents (orders, offers, etc.) ne font qu'insérer dans la table notifications (via leurs Edge Functions intermédiaires).

CREATE OR REPLACE FUNCTION public.handle_push_dispatch()
RETURNS trigger AS $$
BEGIN
  -- Appel asynchrone à l'Edge Function d'envoi
  PERFORM net.http_post(
      url := 'https://mhxanqvyvkffmokpmwjt.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || current_setting('request.jwt.claim.role', true)
      ),
      body := jsonb_build_object(
          'user_id', NEW.user_id,
          'title', NEW.title,
          'body', NEW.body,
          'data', jsonb_build_object(
            'type', NEW.type,
            'model_id', NEW.model_id
          )
      )
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger sur la table notifications
-- Note: On assume que PG_NET est activé.
DROP TRIGGER IF EXISTS on_notification_created ON public.notifications;
CREATE TRIGGER on_notification_created
AFTER INSERT ON public.notifications
FOR EACH ROW
EXECUTE FUNCTION public.handle_push_dispatch();
