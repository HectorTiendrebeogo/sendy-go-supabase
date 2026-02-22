-- ==============================================================================
-- TRIGGER : Mise à jour du Statut de Vérification du Livreur
-- DESCRIPTION : Ce trigger synchronise le statut de vérification des documents
--               avec le statut global de l'utilisateur.
--               Si les documents sont marqués comme 'VERIFIED' ou 'REJECTED',
--               le trigger met à jour :
--               1. La colonne `is_verified` dans la table `public.users`.
--               2. Les métadonnées `user_metadata` dans `auth.users` pour l'authentification.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.update_delivery_person_status()
RETURNS TRIGGER
SECURITY DEFINER
AS $$
BEGIN
  -- Vérifie si le statut est concluant (Vérifié ou Rejeté)
  IF NEW.verification_status IN ('VERIFIED', 'REJECTED') THEN
    
    -- 1. Mise à jour du flag booléen dans la table publique des utilisateurs
    UPDATE public.users
    SET is_verified = (NEW.verification_status = 'VERIFIED')
    WHERE id = NEW.user_id;

    -- 2. Mise à jour des métadonnées d'authentification (utile pour les règles RLS ou le front-end)
    UPDATE auth.users
    SET raw_user_meta_data =
          COALESCE(raw_user_meta_data, '{}'::jsonb)
          || jsonb_build_object('is_verified', NEW.verification_status = 'VERIFIED')
    WHERE id = NEW.user_id;

  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- Suppression de l'ancien trigger s'il existe
DROP TRIGGER IF EXISTS update_delivery_person_status_trigger ON public.user_documents;

-- Création du trigger sur la table `user_documents`
-- Se déclenche uniquement si le statut de vérification a changé
CREATE TRIGGER update_delivery_person_status_trigger
AFTER UPDATE ON public.user_documents
FOR EACH ROW
WHEN (OLD.verification_status IS DISTINCT FROM NEW.verification_status)
EXECUTE FUNCTION public.update_delivery_person_status();
