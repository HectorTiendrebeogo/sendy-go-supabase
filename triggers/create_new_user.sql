-- ==============================================================================
-- TRIGGER : Gestion des Utilisateurs (Création & Mise à jour)
-- DESCRIPTION : Ce fichier contient deux fonctions et triggers pour synchroniser
--               la table `auth.users` (Supabase Auth) avec la table publique `public.users`.
--               1. `handle_new_user` : Crée automatiquement un profil dans `public.users`
--                  lorsqu'un nouvel utilisateur s'inscrit.
--               2. `handle_user_update` : Met à jour le profil dans `public.users`
--                  lorsque les métadonnées de l'utilisateur sont modifiées.
-- ==============================================================================

-- 1. FONCTION : Gestion de la création d'un nouvel utilisateur
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    v_user_type public.user_type;
BEGIN
    -- Insertion des données de base de l'utilisateur dans la table publique
    INSERT INTO public.users (
        id, 
        phone, 
        first_name, 
        last_name, 
        user_type,
        vehicle_type,
        vehicle_registration_number
    )
    VALUES (
        new.id,
        new.phone,
        new.raw_user_meta_data->>'first_name',
        new.raw_user_meta_data->>'last_name',
        (UPPER(new.raw_user_meta_data->>'user_type'))::public.user_type,
        (UPPER(new.raw_user_meta_data->>'vehicle_type'))::public.vehicle_type, -- Peut être NULL si pas un chauffeur
        UPPER(new.raw_user_meta_data->>'vehicle_registration_number') -- Peut être NULL si pas un chauffeur
    );
    RETURN new;
EXCEPTION WHEN OTHERS THEN
    -- Gestion des erreurs lors de la création
    RAISE EXCEPTION 'handle_new_user a échoué : %', SQLERRM;

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- TRIGGER : Exécution après insertion dans auth.users
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- 2. FONCTION : Gestion de la mise à jour d'un utilisateur existant
CREATE OR REPLACE FUNCTION public.handle_user_update()
RETURNS TRIGGER AS $$
BEGIN
    -- Mise à jour des informations dans la table publique
    UPDATE public.users
    SET
        first_name = NEW.raw_user_meta_data->>'first_name',
        last_name = NEW.raw_user_meta_data->>'last_name',
        vehicle_type = (UPPER(new.raw_user_meta_data->>'vehicle_type'))::public.vehicle_type,
        default_address = NEW.raw_user_meta_data->>'default_address',
        /*fcm_token = NEW.raw_user_meta_data->>'fcm_token',
        rating = NEW.raw_user_meta_data->>'rating',*/
        is_active = (NEW.raw_user_meta_data->>'is_active')::boolean,
        updated_at = NOW()
    WHERE id = NEW.id;
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    -- Gestion des erreurs lors de la mise à jour
    RAISE EXCEPTION 'handle_user_update a échoué : %', SQLERRM;

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- TRIGGER : Exécution après mise à jour dans auth.users
DROP TRIGGER IF EXISTS on_auth_user_updated ON auth.users;
CREATE TRIGGER on_auth_user_updated
    AFTER UPDATE ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_user_update();
