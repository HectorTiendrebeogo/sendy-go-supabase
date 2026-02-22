-- ==============================================================================
-- TRIGGER : Gestion de la Localisation des Livreurs
-- DESCRIPTION : Ce trigger gère automatiquement la présence des livreurs dans la table
--               `delivery_persons_locations` en fonction de leur statut `is_active`.
--               - Activation (is_active = TRUE) : Crée une entrée de localisation (0,0)
--                 pour permettre au livreur d'être géolocalisé.
--               - Désactivation (is_active = FALSE) : Supprime l'entrée de localisation,
--                 rendant le livreur invisible sur la carte.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.manage_delivery_person_location()
RETURNS TRIGGER
SECURITY DEFINER
AS $$
BEGIN
  -- CAS 1 : Activation du livreur (is_active passe de FALSE à TRUE)
  IF NEW.is_active = TRUE AND OLD.is_active = FALSE AND NEW.user_type = 'DRIVER' THEN
    -- Création d'une ligne de localisation par défaut.
    -- Les coordonnées réelles seront mises à jour par l'application mobile.
    INSERT INTO public.delivery_persons_locations (delivery_person_id, latitude, longitude)
    VALUES (NEW.id, 0, 0)
    ON CONFLICT (delivery_person_id) DO NOTHING; -- Sécurité pour éviter les erreurs de doublons
  
  -- CAS 2 : Désactivation du livreur (is_active passe de TRUE à FALSE)
  ELSIF NEW.is_active = FALSE AND OLD.is_active = TRUE THEN
    -- Suppression de la ligne de localisation pour retirer le livreur de la carte
    DELETE FROM public.delivery_persons_locations
    WHERE delivery_person_id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Suppression de l'ancien trigger s'il existe
DROP TRIGGER IF EXISTS manage_delivery_person_location_trigger ON public.users;

-- Création du trigger sur la table `users`
-- Se déclenche uniquement si la colonne `is_active` a changé
CREATE TRIGGER manage_delivery_person_location_trigger
AFTER UPDATE ON public.users
FOR EACH ROW
WHEN (OLD.is_active IS DISTINCT FROM NEW.is_active)
EXECUTE FUNCTION public.manage_delivery_person_location();
