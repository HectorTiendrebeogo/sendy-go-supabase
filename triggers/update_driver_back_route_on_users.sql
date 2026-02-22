-- =========================
-- TRIGGER: MISE À JOUR METADATA AUTH DEPUIS LOCALISATION
-- =========================
CREATE OR REPLACE FUNCTION public.handle_driver_location_update_to_auth()
RETURNS TRIGGER 
LANGUAGE plpgsql 
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    current_meta JSONB;
    back_route JSONB;
    new_start JSONB;
BEGIN
    -- Récupérer les métadonnées actuelles de l'utilisateur (auth.users est dans le schéma auth)
    SELECT raw_user_meta_data INTO current_meta
    FROM auth.users
    WHERE id = NEW.delivery_person_id;

    -- Vérifier SI back_route existe dans les métadonnées
    -- On suppose que back_route est stocké comme un objet JSON dans les métadonnées
    IF (current_meta ? 'back_route') AND (current_meta->'back_route') IS NOT NULL AND (current_meta->'back_route') != 'null'::jsonb THEN
        back_route := current_meta->'back_route';
        
        -- Créer le nouvel objet de départ (start)
        new_start := jsonb_build_object('lat', NEW.latitude, 'lng', NEW.longitude);

        -- Mettre à jour la position 'start' dans le JSON back_route
        -- jsonb_set(target, path, new_value)
        back_route := jsonb_set(back_route, '{start}', new_start);

        -- Mettre à jour les métadonnées de l'utilisateur dans auth.users
        -- On met à jour l'objet complet back_route à l'intérieur de raw_user_meta_data
        UPDATE auth.users
        SET raw_user_meta_data = jsonb_set(current_meta, '{back_route}', back_route)
        WHERE id = NEW.delivery_person_id;
    END IF;

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    -- Échouer silencieusement pour éviter de bloquer les mises à jour de localisation si la mise à jour auth échoue
    RETURN NEW;
END;
$$;

-- Supprimer le trigger s'il existe
DROP TRIGGER IF EXISTS on_driver_location_posted_update_auth ON delivery_persons_locations;

-- Créer le trigger
CREATE TRIGGER on_driver_location_posted_update_auth
  AFTER INSERT OR UPDATE ON delivery_persons_locations
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_driver_location_update_to_auth();