-- =========================
-- EXTENSIONS
-- =========================
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- =========================
-- ENUMS
-- =========================
CREATE TYPE user_type AS ENUM ('CLIENT', 'DRIVER', 'ADMIN');
CREATE TYPE vehicle_type AS ENUM ('MOTO', 'TRICYCLE', 'VAN');
CREATE TYPE verification_status AS ENUM ('PENDING', 'VERIFIED', 'REJECTED');
CREATE TYPE offer_status AS ENUM ('PENDING', 'ACCEPTED', 'REJECTED');

CREATE TYPE delivery_status AS ENUM ('CREATED', 'PRICE_ACCEPTED', 'PAID');
CREATE TYPE delivery_progress_status AS ENUM ('PENDING','PICKED_UP','IN_PROGRESS', 'DELIVERED', 'DISPUTED', 'CANCELLED');

CREATE TYPE payment_status AS ENUM ('PENDING', 'SUCCESS', 'FAILED', 'REFUNDED');
CREATE TYPE wallet_tx_type AS ENUM ('CREDIT', 'DEBIT');
CREATE TYPE dispute_status AS ENUM ('OPEN', 'UNDER_REVIEW', 'RESOLVED');
CREATE TYPE package_type AS ENUM ('DOCUMENT', 'FOOD', 'ELECTRONICS', 'CLOTHING', 'OTHER');

CREATE TYPE notification_type AS ENUM (
  'ORDER_CREATED', -- Une nouvelle demande de course
  'ORDER_PICKED_UP', -- Le livreur a récupéré le colis
  'ORDER_DELIVERED', -- Le colis a été livré
  'ORDER_CANCELLED', -- La course a été annulée

  'OFFER_CREATED', -- Une nouvelle offre
  'OFFER_ACCEPTED', -- Offre acceptée par le client
  'OFFER_REJECTED', -- Offre rejetée par le client

  'PAYMENT_RECEIVED', -- Paiement reçu par le livreur
  'PAYMENT_SUCCESS', -- Paiement réussi
  'PAYMENT_FAILED', -- Paiement échoué

  'WALLET_CREDIT', -- Crédit de portefeuille
  'WALLET_DEBIT' -- Débit de portefeuille
);
-- =========================
-- USERS
-- =========================
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  first_name VARCHAR(100),
  last_name VARCHAR(100),
  phone VARCHAR(20) UNIQUE NOT NULL,
  user_type user_type NOT NULL DEFAULT 'CLIENT',
  default_address TEXT,

  is_entreprise BOOLEAN DEFAULT FALSE, -- pour les entreprises
  entreprise_name VARCHAR(100) DEFAULT NULL, -- pour les entreprises

  is_partner_driver BOOLEAN DEFAULT FALSE, -- Pour les livreurs partenaires de l'entreprises

  driver_image_url TEXT DEFAULT NULL, -- pour les conducteurs
  vehicle_type vehicle_type DEFAULT NULL, -- pour les conducteurs
  vehicle_registration_number VARCHAR(20) DEFAULT NULL, -- Immatriculation du véhicule pour les conducteurs
  rating NUMERIC(2,1) DEFAULT NULL, -- pour les conducteurs
  is_active BOOLEAN DEFAULT TRUE, -- pour les conducteurs

  is_verified BOOLEAN DEFAULT FALSE, -- pour les clients et les entreprises

  fcm_token TEXT UNIQUE DEFAULT NULL, -- pour les notifications

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_users_fcm_token ON users(fcm_token);


CREATE TABLE IF NOT EXISTS user_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES users(id),
  identity_document_url TEXT NOT NULL, -- Carte d'identité ou passeport
  identity_document_verso_url TEXT NOT NULL, -- Carte d'identité ou passeport
  vehicle_document_url TEXT NOT NULL, -- Carte grise
  vehicle_document_verso_url TEXT NOT NULL, -- Carte grise
  verification_status verification_status DEFAULT 'PENDING', -- pour les conducteurs
  
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS entreprise_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code VARCHAR(10) NOT NULL,
  discount_percentage NUMERIC(5,2) NOT NULL DEFAULT 1,
  user_id UUID NOT NULL UNIQUE REFERENCES users(id),

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- =========================
-- DELIVERY PERSONS LOCATIONS
-- =========================
CREATE TABLE IF NOT EXISTS delivery_persons_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_person_id UUID UNIQUE REFERENCES users(id),
  latitude NUMERIC(9,6) NOT NULL,
  longitude NUMERIC(9,6) NOT NULL,

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);
ALTER PUBLICATION supabase_realtime ADD TABLE delivery_persons_locations;

-- =========================
-- ORDERS
-- =========================
CREATE TABLE IF NOT EXISTS orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id), -- Client ou Entreprise

  pickup_address_name TEXT NOT NULL,
  delivery_address_name TEXT NOT NULL,
  pickup_latitude NUMERIC(9,6) NOT NULL,
  pickup_longitude NUMERIC(9,6) NOT NULL,
  delivery_latitude NUMERIC(9,6) NOT NULL,
  delivery_longitude NUMERIC(9,6) NOT NULL,
  delivery_distance NUMERIC(6,2) NOT NULL,
  delivery_duration NUMERIC(6,2) NOT NULL,
  sender_user_name VARCHAR(200) NOT NULL,
  sender_user_phone VARCHAR(20) NOT NULL,
  delivery_user_name VARCHAR(200) NOT NULL,
  delivery_user_phone VARCHAR(20) NOT NULL,

  package_type package_type,
  is_package_fragile BOOLEAN DEFAULT FALSE,
  package_price NUMERIC(10,2), -- Valeur du colis
  package_image_url TEXT NOT NULL,

  vehicle_type vehicle_type DEFAULT NULL,

  instructions TEXT,

  offers_count INT DEFAULT 0,

  delivery_price NUMERIC(10,2), -- Prix de la course
  delivery_fee NUMERIC(10,2), -- Commission de la plateforme
  delivery_status delivery_status DEFAULT 'CREATED',
  delivery_progress_status delivery_progress_status DEFAULT NULL,
  
  delivery_image_url TEXT, -- Photo du colis après livraison
  pickup_time TIMESTAMP,
  delivery_time TIMESTAMP,

  has_review BOOLEAN DEFAULT FALSE,

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);
ALTER PUBLICATION supabase_realtime ADD TABLE orders;


-- =========================
-- OFFERS
-- =========================
CREATE TABLE IF NOT EXISTS offers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID REFERENCES orders(id) ON DELETE CASCADE,
  delivery_person_id UUID REFERENCES users(id),
  proposed_price NUMERIC(10,2) NOT NULL, -- Prix proposé par le livreur
  offer_status offer_status DEFAULT 'PENDING',

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),

  UNIQUE(order_id, delivery_person_id)
);

-- Vue pour afficher les commandes disponibles
-- Une commande est disponible si elle n'a aucune offre acceptée.
CREATE OR REPLACE VIEW available_orders AS
SELECT o.*
FROM orders o
WHERE NOT EXISTS (
  SELECT 1 
  FROM offers f 
  WHERE f.order_id = o.id 
  AND f.offer_status = 'ACCEPTED'
)
ORDER BY o.created_at DESC;

ALTER PUBLICATION supabase_realtime ADD TABLE offers;
CREATE INDEX idx_offers_order_id_delivery_person_id ON offers(order_id,delivery_person_id);

-- =========================
-- OTPs pour les livraisons
-- =========================
CREATE TABLE IF NOT EXISTS otps (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID UNIQUE REFERENCES orders(id) ON DELETE CASCADE,
  code VARCHAR(10) NOT NULL,
  is_used BOOLEAN DEFAULT FALSE,
  expires_at TIMESTAMP NOT NULL,

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_otps_code ON otps(code);

-- =========================
-- PROMO CODES
-- =========================
CREATE TABLE IF NOT EXISTS promo_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL,
    discount_percentage NUMERIC(5,2) NOT NULL,
    vehicle_type vehicle_type NOT NULL,

    total_uses INTEGER DEFAULT 0,
    
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- =========================
-- PAYMENTS
-- =========================
CREATE TABLE IF NOT EXISTS client_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID UNIQUE REFERENCES orders(id),
  client_id UUID REFERENCES users(id),
  amount NUMERIC(10,2) NOT NULL,
  discount_amount NUMERIC(10,2) NOT NULL DEFAULT 0,

  transaction_id TEXT NOT NULL, -- ID de transaction de l'intégrateur de paiement
  operator_name VARCHAR(50) NOT NULL, -- Nom de l'opérateur de paiement utilisé (ex: Orange Money, Moov Money, etc.)
  promo_code_id UUID REFERENCES promo_codes(id),
  
  status payment_status DEFAULT 'PENDING',

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- =========================
-- WALLETS
-- =========================
CREATE TABLE IF NOT EXISTS wallets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES users(id), -- Livreur ou Entreprise partenaire
  balance NUMERIC(12,2) DEFAULT 0, -- Balance disponible
  locked_balance NUMERIC(12,2) DEFAULT 0, -- Balance bloquée

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- =========================
-- WALLET TRANSACTIONS
-- =========================
CREATE TABLE IF NOT EXISTS wallet_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  wallet_id UUID REFERENCES wallets(id),
  -- order_id UUID REFERENCES orders(id),
  wallet_tx_type wallet_tx_type,
  amount NUMERIC(12,2),

  transaction_id TEXT NOT NULL, -- ID de transaction de l'intégrateur de paiement
  operator_name VARCHAR(50) NOT NULL, -- Nom de l'opérateur de paiement utilisé (ex: Orange Money, Moov Money, etc.)
  status payment_status DEFAULT 'PENDING',

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- =========================
-- REVIEWS
-- =========================
CREATE TABLE IF NOT EXISTS reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID UNIQUE REFERENCES orders(id),
  client_id UUID REFERENCES users(id), -- Client ou Entreprise
  delivery_person_id UUID REFERENCES users(id), -- Livreur
  rating INTEGER CHECK (rating BETWEEN 1 AND 5),

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- =========================
-- DISPUTES
-- =========================
CREATE TABLE IF NOT EXISTS disputes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID UNIQUE REFERENCES orders(id),
  raised_by UUID REFERENCES users(id), -- Client ou Livreur
  status dispute_status DEFAULT 'OPEN',

  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);


-- Migration: Création de la table otp_verifications

CREATE TABLE IF NOT EXISTS otp_verifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone TEXT NOT NULL, -- Numéro de téléphone
    full_phone TEXT NOT NULL, -- Numéro de téléphone complet avec code pays
    otp_token TEXT NOT NULL, -- Token OTP
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL
);

-- Index
CREATE INDEX IF NOT EXISTS idx_otp_verifications_phone ON otp_verifications(phone);
CREATE INDEX IF NOT EXISTS idx_otp_verifications_expires_at ON otp_verifications(expires_at);

CREATE TABLE IF NOT EXISTS platform_balances (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    total_balance NUMERIC(12,2) DEFAULT 0, -- Montant total des transactions des livreurs
    total_platform_fee NUMERIC(12,2) DEFAULT 0, -- Montant total des commissions de la plateforme
    total_promo_code_discount NUMERIC(12,2) DEFAULT 0, -- Montant total des réductions de codes promo
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- =========================
-- DRIVER ADDRESSES
-- =========================
CREATE TABLE IF NOT EXISTS driver_addresses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  address TEXT NOT NULL,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- =========================
-- NOTIFICATIONS
-- =========================

CREATE TABLE IF NOT EXISTS notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  body text not null,
  type notification_type, -- Ex: 'order_status', 'payment', 'info'
  data JSONB, -- Pour stocker l'ID de la commande ou des métadonnées de navigation
  model_id uuid,
  is_read boolean not null default false,
  created_at timestamp with time zone not null default now()
);

-- =========================
-- TRIGGER: UPDATE BACK ROUTE
-- =========================
-- CREATE OR REPLACE FUNCTION public.handle_user_back_route_update()
-- RETURNS TRIGGER 
-- LANGUAGE plpgsql 
-- SECURITY DEFINER SET search_path = public
-- AS $$
-- BEGIN
  -- Check if back_route changed in metadata
  -- IF (NEW.raw_user_meta_data->'back_route') IS DISTINCT FROM (OLD.raw_user_meta_data->'back_route') THEN
      -- UPDATE public.users
      -- SET back_route = NEW.raw_user_meta_data->'back_route'
      -- WHERE id = NEW.id;
  -- END IF;
  -- RETURN NEW;
-- END;
-- $$;

-- Drop trigger if exists to avoid error
-- DROP TRIGGER IF EXISTS on_auth_user_back_route_updated ON auth.users;

-- Create trigger
-- CREATE TRIGGER on_auth_user_back_route_updated
--   AFTER UPDATE ON auth.users
--   FOR EACH ROW
--   EXECUTE FUNCTION public.handle_user_back_route_update();