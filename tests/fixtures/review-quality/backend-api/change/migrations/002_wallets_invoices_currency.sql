-- Store-credit wallets, invoices issued by the billing worker, and per-order currency.

CREATE TABLE wallets (
  user_id INTEGER PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
  balance_cents INTEGER NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE invoices (
  id SERIAL PRIMARY KEY,
  order_id INTEGER NOT NULL UNIQUE REFERENCES orders (id),
  user_id INTEGER NOT NULL REFERENCES users (id),
  amount_cents INTEGER NOT NULL,
  currency CHAR(3) NOT NULL,
  billing_name TEXT NOT NULL,
  billing_address TEXT NOT NULL,
  issued_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX invoices_user_id_idx ON invoices (user_id);

ALTER TABLE orders ADD COLUMN currency CHAR(3) NOT NULL;
