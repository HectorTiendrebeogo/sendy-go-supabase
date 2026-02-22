-- ==============================================================================
-- TRIGGER : Mise à jour des Soldes (Wallet & Plateforme)
-- DESCRIPTION : Ce trigger s'exécute après l'insertion d'une transaction dans `wallet_transactions`.
--               Il met à jour deux types de soldes en fonction du type de transaction (CREDIT/DEBIT) :
--               1. Le solde individuel du portefeuille de l'utilisateur (`wallets`).
--               2. Le solde global de la plateforme (`platform_balances`).
-- ==============================================================================

CREATE OR REPLACE FUNCTION update_wallet_balance()
RETURNS TRIGGER AS $$
BEGIN
  -- Initialisation de la table `platform_balances` si nécessaire
  IF NOT EXISTS (SELECT 1 FROM platform_balances) THEN
    INSERT INTO platform_balances (total_balance, total_platform_fee, total_promo_code_discount)
    VALUES (0, 0, 0);
  END IF;

  -- Exécution uniquement si la transaction a le statut 'SUCCESS'
  IF NEW.status = 'SUCCESS' THEN
    
    -- CAS 1 : Crédit (Ajout d'argent)
    IF NEW.wallet_tx_type = 'CREDIT' THEN
      -- Mise à jour du wallet de l'utilisateur (+ montant)
      UPDATE wallets
      SET balance = balance + NEW.amount,
          updated_at = NOW()
      WHERE id = NEW.wallet_id;
      
      -- Mise à jour du solde global de la plateforme (+ montant)
      UPDATE platform_balances
      SET total_balance = total_balance + NEW.amount,
          updated_at = NOW()
      WHERE id IS NOT NULL;

    -- CAS 2 : Débit (Retrait d'argent)
    ELSIF NEW.wallet_tx_type = 'DEBIT' THEN
      -- Mise à jour du wallet de l'utilisateur (- montant)
      UPDATE wallets
      SET balance = balance - NEW.amount,
          updated_at = NOW()
      WHERE id = NEW.wallet_id;

      -- Mise à jour du solde global de la plateforme (- montant)
      UPDATE platform_balances
      SET total_balance = total_balance - NEW.amount,
          updated_at = NOW()
      WHERE id IS NOT NULL;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Suppression de l'ancien trigger s'il existe
DROP TRIGGER IF EXISTS on_wallet_transaction_insert ON wallet_transactions;

-- Création du trigger sur la table `wallet_transactions`
CREATE TRIGGER on_wallet_transaction_insert
AFTER INSERT ON wallet_transactions
FOR EACH ROW
EXECUTE FUNCTION update_wallet_balance();