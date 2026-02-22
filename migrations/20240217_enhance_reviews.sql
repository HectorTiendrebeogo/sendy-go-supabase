-- Function to update driver rating and mark order as reviewed on new/updated review
CREATE OR REPLACE FUNCTION update_driver_rating()
RETURNS TRIGGER AS $$
DECLARE
    new_avg_rating NUMERIC(2,1);
BEGIN
    -- 1. Calculate the new average rating for the driver involved
    SELECT ROUND(AVG(rating)::numeric, 1)
    INTO new_avg_rating
    FROM reviews
    WHERE delivery_person_id = NEW.delivery_person_id;

    -- 2. Update the driver's rating in the users table
    UPDATE users
    SET rating = new_avg_rating
    WHERE id = NEW.delivery_person_id;

    -- 2b. Sync the rating to auth.users metadata
    UPDATE auth.users
    SET raw_user_meta_data = 
        jsonb_set(
            COALESCE(raw_user_meta_data, '{}'::jsonb),
            '{rating}',
            to_jsonb(new_avg_rating)
        )
    WHERE id = NEW.delivery_person_id;

    -- 3. Mark the order as having a review
    UPDATE orders
    SET has_review = TRUE
    WHERE id = NEW.order_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create the trigger
DROP TRIGGER IF EXISTS trigger_update_driver_rating ON reviews;
CREATE TRIGGER trigger_update_driver_rating
AFTER INSERT OR UPDATE ON reviews
FOR EACH ROW
EXECUTE FUNCTION update_driver_rating();
