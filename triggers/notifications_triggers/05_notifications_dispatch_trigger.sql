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
