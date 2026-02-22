-- ==============================================================================
-- TRIGGER : Création Automatique de Portefeuille (Wallet)
-- DESCRIPTION : Ce fichier contient deux triggers distincts pour la création de wallets :
--               1. `create_wallet_for_driver` : Crée un wallet vide lorsqu'un nouvel utilisateur
--                  de type 'DRIVER' (Livreur) est inséré dans la table `users`.
--               2. `create_wallet_for_entreprise` : Crée un wallet vide lorsqu'une nouvelle
--                  entreprise est ajoutée dans la table `entreprise_codes`.
-- ==============================================================================

-- 1. FONCTION & TRIGGER : Pour les Livreurs (Drivers)
CREATE OR REPLACE FUNCTION create_wallet_for_driver()
RETURNS TRIGGER AS $$
BEGIN
  -- Initialisation d'un portefeuille avec un solde de 0
  INSERT INTO public.wallets (user_id, balance, locked_balance)
  VALUES (NEW.id, 0, 0);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_create_wallet_driver ON users;

CREATE TRIGGER trg_create_wallet_driver
AFTER INSERT ON users
FOR EACH ROW
WHEN (NEW.user_type = 'DRIVER') -- Condition : Seuelement pour les livreurs
EXECUTE FUNCTION create_wallet_for_driver();


-- 2. FONCTION & TRIGGER : Pour les Entreprises
-- CREATE OR REPLACE FUNCTION create_wallet_for_entreprise()
-- RETURNS TRIGGER AS $$
-- BEGIN
--   -- Initialisation d'un portefeuille avec un solde de 0 pour l'entreprise
--   INSERT INTO public.wallets (user_id, balance, locked_balance)
--   VALUES (NEW.user_id, 0, 0);
--   RETURN NEW;
-- END;
-- $$ LANGUAGE plpgsql;

-- DROP TRIGGER IF EXISTS trg_create_wallet_entreprise ON entreprise_codes;

-- CREATE TRIGGER trg_create_wallet_entreprise
-- AFTER INSERT ON entreprise_codes
-- FOR EACH ROW
-- EXECUTE FUNCTION create_wallet_for_entreprise();
