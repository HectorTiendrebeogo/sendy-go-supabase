-- =========================
-- WALLET AUTO CREATION
-- =========================
CREATE OR REPLACE FUNCTION create_wallet_for_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO wallets (user_id, balance, locked_balance)
  VALUES (NEW.id, 0, 0);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_create_wallet
AFTER INSERT ON users
FOR EACH ROW
EXECUTE FUNCTION create_wallet_for_user();

-- =========================
-- OTP GENERATION AFTER PAYMENT
-- =========================
CREATE OR REPLACE FUNCTION generate_otp_after_payment()
RETURNS TRIGGER AS $$
DECLARE
  otp_code TEXT;
BEGIN
  IF NEW.status = 'SUCCESS' THEN
    otp_code := LPAD(FLOOR(RANDOM() * 1000000)::TEXT, 6, '0');

    INSERT INTO otps (order_id, code, expires_at)
    VALUES (NEW.order_id, otp_code, NOW() + INTERVAL '12 hours');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_generate_otp
AFTER UPDATE OF status ON payments
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION generate_otp_after_payment();

-- =========================
-- ACCEPT SINGLE OFFER
-- =========================
CREATE OR REPLACE FUNCTION accept_single_offer()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.is_accepted = TRUE THEN
    UPDATE offers
    SET is_accepted = FALSE
    WHERE order_id = NEW.order_id
      AND id <> NEW.id;

    INSERT INTO deliveries (order_id, delivery_person_id, status)
    VALUES (NEW.order_id, NEW.delivery_person_id, 'ASSIGNED');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_accept_single_offer
AFTER UPDATE OF is_accepted ON offers
FOR EACH ROW
WHEN (NEW.is_accepted = TRUE)
EXECUTE FUNCTION accept_single_offer();

-- =========================
-- SYNC DELIVERY → ORDER STATUS
-- =========================
CREATE OR REPLACE FUNCTION sync_order_status()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE orders
  SET status = NEW.status
  WHERE id = NEW.order_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_order_status
AFTER UPDATE OF status ON deliveries
FOR EACH ROW
EXECUTE FUNCTION sync_order_status();

-- =========================
-- VALIDATE DELIVERY WITH OTP
-- =========================
CREATE OR REPLACE FUNCTION validate_delivery_with_otp()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.is_used = TRUE THEN
    UPDATE deliveries
    SET status = 'CONFIRMED',
        delivery_time = NOW()
    WHERE order_id = NEW.order_id;

    UPDATE orders
    SET status = 'COMPLETED'
    WHERE id = NEW.order_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_delivery
AFTER UPDATE OF is_used ON otps
FOR EACH ROW
WHEN (NEW.is_used = TRUE)
EXECUTE FUNCTION validate_delivery_with_otp();

-- =========================
-- RELEASE PAYMENT (ESCROW)
-- =========================
CREATE OR REPLACE FUNCTION release_payment_to_delivery()
RETURNS TRIGGER AS $$
DECLARE
  total NUMERIC;
  commission NUMERIC;
  net_amount NUMERIC;
  delivery_user UUID;
BEGIN
  IF NEW.status IN ('COMPLETED', 'AUTO_COMPLETED') THEN
    SELECT amount, commission
    INTO total, commission
    FROM payments
    WHERE order_id = NEW.id;

    net_amount := total - commission;

    SELECT delivery_person_id
    INTO delivery_user
    FROM deliveries
    WHERE order_id = NEW.id;

    UPDATE wallets
    SET balance = balance + net_amount
    WHERE user_id = delivery_user;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_release_payment
AFTER UPDATE OF status ON orders
FOR EACH ROW
EXECUTE FUNCTION release_payment_to_delivery();

-- =========================
-- UPDATE DELIVERY RATING
-- =========================
CREATE OR REPLACE FUNCTION update_delivery_rating()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE delivery_persons
  SET rating = (
    SELECT AVG(rating)
    FROM reviews
    WHERE delivery_person_id = NEW.delivery_person_id
  )
  WHERE user_id = NEW.delivery_person_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_rating
AFTER INSERT ON reviews
FOR EACH ROW
EXECUTE FUNCTION update_delivery_rating();
