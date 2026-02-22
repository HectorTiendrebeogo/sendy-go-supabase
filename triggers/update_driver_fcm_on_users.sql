-- Function to update driver fcm token in supabase auth.users metadata
CREATE OR REPLACE FUNCTION update_driver_fcm()
RETURNS TRIGGER AS $$
BEGIN
    -- 1. Update driver fcm token in auth.users metadata
    UPDATE auth.users
    SET raw_user_meta_data = 
        jsonb_set(
            COALESCE(raw_user_meta_data, '{}'::jsonb),
            '{fcm_token}',
            to_jsonb(NEW.fcm_token)
        )
    WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create the trigger
DROP TRIGGER IF EXISTS trigger_update_driver_fcm ON users;
CREATE TRIGGER trigger_update_driver_fcm
AFTER INSERT OR UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION update_driver_fcm();
