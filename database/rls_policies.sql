-- 0. PERMISSIONS DE BASE (GRANTS)
-- Accorder les permissions CRUD de base aux utilisateurs authentifiés
-- Les politiques RLS (ci-dessous) limiteront ensuite ce qu'ils peuvent réellement faire ligne par ligne.
GRANT SELECT, INSERT, UPDATE, DELETE ON orders TO authenticated;
-- Permission de lecture sur la vue pour les utilisateurs authentifiés (Livreurs)
GRANT SELECT ON available_orders TO authenticated;

-- Activer la sécurité niveau ligne (RLS) sur la table orders
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- Nettoyer les anciennes politiques pour éviter les conflits
DROP POLICY IF EXISTS "Visibility Policy" ON orders;
DROP POLICY IF EXISTS "Clients Manage Orders" ON orders;
DROP POLICY IF EXISTS "Clients Insert Orders" ON orders;
DROP POLICY IF EXISTS "Clients Update Orders" ON orders;
DROP POLICY IF EXISTS "Clients Delete Orders" ON orders;

-- 1. POLITIQUE DE LECTURE (SELECT)
-- Les clients voient leurs propres commandes.
-- Les chauffeurs et admins voient TOUTES les commandes.
CREATE POLICY "Visibility Policy"
ON orders
FOR SELECT
TO authenticated
USING (
  auth.uid() = user_id -- Le client voit sa commande
  OR 
  EXISTS ( -- Le chauffeur ou admin voit tout
    SELECT 1 FROM users 
    WHERE id = auth.uid() 
    AND user_type IN ('DRIVER', 'ADMIN')
  )
);

-- 2. POLITIQUE D'INSERTION (INSERT)
-- Un client peut créer une commande pour lui-même
CREATE POLICY "Clients Insert Orders"
ON orders
FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() = user_id 
  AND 
  EXISTS (
    SELECT 1 FROM users 
    WHERE id = auth.uid() 
    AND user_type = 'CLIENT'
  )
);

-- 3. POLITIQUE DE MISE A JOUR (UPDATE)
-- Un client peut modifier sa propre commande
CREATE POLICY "Clients Update Orders"
ON orders
FOR UPDATE
TO authenticated
USING (
  auth.uid() = user_id 
  AND 
  EXISTS (
    SELECT 1 FROM users 
    WHERE id = auth.uid() 
    AND user_type = 'CLIENT'
  )
);

-- 4. POLITIQUE DE SUPPRESSION (DELETE)
-- Un client peut supprimer sa commande SEULEMENT si aucune offre n'a été acceptée
CREATE POLICY "Clients Delete Orders"
ON orders
FOR DELETE
TO authenticated
USING (
  auth.uid() = user_id 
  AND 
  NOT EXISTS ( -- Aucune offre acceptée sur cette commande
    SELECT 1 FROM offers 
    WHERE order_id = orders.id 
    AND offer_status = 'ACCEPTED'
  )
);

-----------------------------------------------------------
-----------------------------------------------------------
-- USERS TABLES
-----------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON users TO authenticated;

-- Activer la sécurité niveau ligne (RLS) sur la table users
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- Nettoyer les anciennes politiques pour éviter les conflits
DROP POLICY IF EXISTS "Users can view all users" ON users;
DROP POLICY IF EXISTS "Users can create their own profile" ON users;
DROP POLICY IF EXISTS "Users can update their own profile" ON users;

-- 1. POLITIQUE DE LECTURE (SELECT)
-- Les utilisateurs voient TOUTES les informations des autres utilisateurs
CREATE POLICY "Users can view all users"
ON users
FOR SELECT
TO authenticated
USING (TRUE);

-- 2. POLITIQUE D'INSERTION (INSERT)
-- Un utilisateur peut créer son propre profil
CREATE POLICY "Users can create their own profile"
ON users
FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() = id
);

-- 3. POLITIQUE DE MISE A JOUR (UPDATE)
-- Un utilisateur peut modifier SON PROPRE profil
CREATE POLICY "Users can update their own profile"
ON users
FOR UPDATE
TO authenticated
USING (
  auth.uid() = id
);

-----------------------------------------------------------
-- WALLETS TABLES
-----------------------------------------------------------
-- Ensure permissions are granted
GRANT ALL ON wallets TO authenticated;
GRANT ALL ON wallets TO service_role; -- Ensure service role has access

-- Enable RLS
ALTER TABLE wallets ENABLE ROW LEVEL SECURITY;

-- Clean up old policies
DROP POLICY IF EXISTS "Users can view their own wallet" ON wallets;
DROP POLICY IF EXISTS "Users can insert their own wallet" ON wallets;
DROP POLICY IF EXISTS "Users can update their own wallet" ON wallets;

-- 1. SELECT Policy
CREATE POLICY "Users can view their own wallet"
ON wallets
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- 2. INSERT Policy (Required for triggers running as invoker)
CREATE POLICY "Users can insert their own wallet"
ON wallets
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

-- 3. UPDATE Policy (Optional, but good for completeness if logic requires it later)
CREATE POLICY "Users can update their own wallet"
ON wallets
FOR UPDATE
TO authenticated
USING (auth.uid() = user_id);

-----------------------------------------------------------
-- WALLET TRANSACTIONS TABLES
-----------------------------------------------------------
GRANT ALL ON wallet_transactions TO authenticated;
ALTER TABLE wallet_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own wallet transactions" ON wallet_transactions;
CREATE POLICY "Users can view their own wallet transactions"
ON wallet_transactions
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM wallets
    WHERE wallets.id = wallet_transactions.wallet_id
    AND wallets.user_id = auth.uid()
  )
);



-----------------------------------------------------------
-- USERS DOCUMENTS TABLES
-----------------------------------------------------------
GRANT ALL ON user_documents TO authenticated;
ALTER TABLE user_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users or Admin can view users owns documents" ON user_documents;
CREATE POLICY "Users or Admin can view users owns documents"
ON user_documents
FOR SELECT
TO authenticated
USING (
  auth.uid() = user_id 
  OR 
  EXISTS (
    SELECT 1 FROM users 
    WHERE id = auth.uid() 
    AND user_type = 'ADMIN'
  )
);


DROP POLICY IF EXISTS "Users can create their own users documents" ON user_documents;
CREATE POLICY "Users can create their own users documents"
ON user_documents
FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() = user_id
);


DROP POLICY IF EXISTS "Users can update their own users documents" ON user_documents;
CREATE POLICY "Users can update their own users documents"
ON user_documents
FOR UPDATE
TO authenticated
USING (
  auth.uid() = user_id
);


DROP POLICY IF EXISTS "Only Admin can delete users documents" ON user_documents;
CREATE POLICY "Only Admin can delete users documents"
ON user_documents
FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM users
    WHERE id = auth.uid()
    AND user_type = 'ADMIN'
  )
);

-----------------------------------------------------------
-- OFFERS TABLES
-----------------------------------------------------------
GRANT ALL ON offers TO authenticated;
ALTER TABLE offers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admin can view all offers. Driver can view their own offers. Client can view offers relative to their orders" ON offers;
CREATE POLICY "Admin can view all offers. Driver can view their own offers. Client can view offers relative to their orders"
ON offers
FOR SELECT
TO authenticated
USING (
  auth.uid() = delivery_person_id 
  OR 
  EXISTS (
    SELECT 1 FROM orders
    WHERE orders.id = offers.order_id
    AND orders.user_id = auth.uid()
  )
  OR 
  EXISTS (
    SELECT 1 FROM users
    WHERE id = auth.uid()
    AND user_type = 'ADMIN'
  )
);

DROP POLICY IF EXISTS "Drivers can create their own offers" ON offers;
CREATE POLICY "Drivers can create their own offers"
ON offers
FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() = delivery_person_id
);

DROP POLICY IF EXISTS "Drivers can update their own offers" ON offers;
CREATE POLICY "Drivers can update their own offers"
ON offers
FOR UPDATE
TO authenticated
USING (
  auth.uid() = delivery_person_id
);

DROP POLICY IF EXISTS "Drivers can delete their own offers" ON offers;
CREATE POLICY "Drivers can delete their own offers"
ON offers
FOR DELETE
TO authenticated
USING (
  auth.uid() = delivery_person_id
);

-- Policy for Clients to accept offers (Update offer_status)
DROP POLICY IF EXISTS "Clients can accept offers for their orders" ON offers;
CREATE POLICY "Clients can accept offers for their orders"
ON offers
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM orders
    WHERE orders.id = offers.order_id
    AND orders.user_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM orders
    WHERE orders.id = offers.order_id
    AND orders.user_id = auth.uid()
  )
);

-----------------------------------------------------------
-- DELIVERY PERSONS LOCATIONS TABLES
-----------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON delivery_persons_locations TO authenticated;

ALTER TABLE delivery_persons_locations ENABLE ROW LEVEL SECURITY;

-- 1. SELECT Policy
-- Tout le monde peut voir les positions des livreurs (pour les afficher sur la carte)
DROP POLICY IF EXISTS "View Delivery Persons Locations" ON delivery_persons_locations;
CREATE POLICY "View Delivery Persons Locations"
ON delivery_persons_locations
FOR SELECT
TO authenticated
USING (true);

-- 2. INSERT Policy
-- Le livreur peut insérer sa propre position (généralement géré par trigger)
DROP POLICY IF EXISTS "Delivery Persons can insert their own location" ON delivery_persons_locations;
CREATE POLICY "Delivery Persons can insert their own location"
ON delivery_persons_locations
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = delivery_person_id);

-- 3. UPDATE Policy
-- Le livreur met à jour sa propre position
DROP POLICY IF EXISTS "Delivery Persons can update their own location" ON delivery_persons_locations;
CREATE POLICY "Delivery Persons can update their own location"
ON delivery_persons_locations
FOR UPDATE
TO authenticated
USING (auth.uid() = delivery_person_id);

-- 4. DELETE Policy
-- Le livreur peut supprimer sa propre position (généralement géré par trigger)
DROP POLICY IF EXISTS "Delivery Persons can delete their own location" ON delivery_persons_locations;
CREATE POLICY "Delivery Persons can delete their own location"
ON delivery_persons_locations
FOR DELETE
TO authenticated
USING (auth.uid() = delivery_person_id);



-----------------------------------------------------------
-- CLIENTS TRANSACTIONS TABLES
-----------------------------------------------------------
GRANT ALL ON client_payments TO authenticated;
GRANT ALL ON client_payments TO service_role;

ALTER TABLE client_payments ENABLE ROW LEVEL SECURITY;

-- 1. SELECT Policy
-- Un Client peut voir les transactions pour lesquelles il est concerné.
-- Un Admin peut voir toutes les transactions.
DROP POLICY IF EXISTS "View Clients Transactions Policy" ON client_payments;
CREATE POLICY "View Clients Transactions Policy"
ON client_payments
FOR SELECT
TO authenticated
USING (true);
/*USING (
  auth.uid() = client_id 
  OR 
  EXISTS (
    SELECT 1 FROM users 
    WHERE id = auth.uid() 
    AND user_type = 'ADMIN'
  )
);*/

-- 2. INSERT Policy
-- Le client peut insérer sa propre transaction
DROP POLICY IF EXISTS "Insert Clients Transactions Policy" ON client_payments;
CREATE POLICY "Insert Clients Transactions Policy"
ON client_payments
FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() = client_id
  AND 
  EXISTS (
    SELECT 1 FROM users
    WHERE id = client_id
    AND user_type = 'CLIENT'
  )
);

-- 3. UPDATE Policy
-- Le client peut mettre à jour sa propre transaction
DROP POLICY IF EXISTS "Update Clients Transactions Policy" ON client_payments;
CREATE POLICY "Update Clients Transactions Policy"
ON client_payments
FOR UPDATE
TO authenticated
USING (
  auth.uid() = client_id 
);


-----------------------------------------------------------
-- PROMO CODES TABLES
-----------------------------------------------------------
GRANT ALL ON promo_codes TO authenticated;
GRANT ALL ON promo_codes TO service_role;

ALTER TABLE promo_codes ENABLE ROW LEVEL SECURITY;

-- 1. SELECT Policy
-- Tout le monde peut voir les codes promo (pour les afficher sur la carte)
DROP POLICY IF EXISTS "View Promo Codes Policy" ON promo_codes;
CREATE POLICY "View Promo Codes Policy"
ON promo_codes
FOR SELECT
TO authenticated
USING (true);


-----------------------------------------------------------
-- REVIEWS TABLES
-----------------------------------------------------------
GRANT ALL ON reviews TO authenticated;
GRANT ALL ON reviews TO service_role;

ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;

-- 1. SELECT Policy
-- Tout le monde peut voir les avis (pour les afficher sur la carte)
DROP POLICY IF EXISTS "View Reviews Policy" ON reviews;
CREATE POLICY "View Reviews Policy"
ON reviews
FOR SELECT
TO authenticated
USING (true);

-- 2. INSERT Policy
-- Le client peut insérer son propre avis
DROP POLICY IF EXISTS "Insert Reviews Policy" ON reviews;
CREATE POLICY "Insert Reviews Policy"
ON reviews
FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() = client_id
  AND 
  EXISTS (
    SELECT 1 FROM users
    WHERE id = client_id
    AND user_type = 'CLIENT'
  )
);

-- 3. UPDATE Policy
-- Le client peut mettre à jour son propre avis
DROP POLICY IF EXISTS "Update Reviews Policy" ON reviews;
CREATE POLICY "Update Reviews Policy"
ON reviews
FOR UPDATE
TO authenticated
USING (
  auth.uid() = client_id 
);


-- RLS Policies
GRANT ALL ON driver_addresses TO authenticated;
GRANT ALL ON driver_addresses TO service_role;

ALTER TABLE driver_addresses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Drivers can view their own addresses" ON driver_addresses;
DROP POLICY IF EXISTS "Drivers can insert their own addresses" ON driver_addresses;
DROP POLICY IF EXISTS "Drivers can update their own addresses" ON driver_addresses;
DROP POLICY IF EXISTS "Drivers can delete their own addresses" ON driver_addresses;

CREATE POLICY "Drivers can view their own addresses" ON driver_addresses
  FOR SELECT USING (auth.uid() = driver_id);

CREATE POLICY "Drivers can insert their own addresses" ON driver_addresses
  FOR INSERT WITH CHECK (auth.uid() = driver_id);

CREATE POLICY "Drivers can update their own addresses" ON driver_addresses
  FOR UPDATE USING (auth.uid() = driver_id);

CREATE POLICY "Drivers can delete their own addresses" ON driver_addresses
  FOR DELETE USING (auth.uid() = driver_id);



-----------------------------------------------------------
-- NOTIFICATIONS TABLES
-----------------------------------------------------------
GRANT ALL ON notifications TO authenticated;
GRANT ALL ON notifications TO service_role;

ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own notifications" ON notifications;
DROP POLICY IF EXISTS "Users can update their own notifications" ON notifications;

CREATE POLICY "Users can view their own notifications" ON notifications
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own notifications" ON notifications
  FOR UPDATE USING (auth.uid() = user_id); -- Pour marquer comme lu