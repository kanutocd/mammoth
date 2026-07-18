CREATE TABLE IF NOT EXISTS orders (
  id BIGSERIAL PRIMARY KEY,
  customer_email TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'paid', 'shipped', 'received', 'cancelled')),
  total_cents INTEGER NOT NULL CHECK (total_cents > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Keep an existing quickstart database compatible when new demo statuses are
-- introduced. PostgreSQL names the inline constraint orders_status_check.
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_status_check;
ALTER TABLE orders ADD CONSTRAINT orders_status_check
  CHECK (status IN ('pending', 'paid', 'shipped', 'received', 'cancelled'));

CREATE TABLE IF NOT EXISTS payments (
  id BIGSERIAL PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES orders(id),
  amount_cents INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'captured',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT payments_entry_check CHECK (
    (status = 'captured' AND amount_cents > 0) OR
    (status = 'reversed' AND amount_cents < 0)
  )
);

-- Migrate an existing one-payment-per-order quickstart database to an
-- append-only accounting-entry model that permits negative reversals.
ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_order_id_key;
ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_amount_cents_check;
ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_status_check;
ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_entry_check;
ALTER TABLE payments ADD CONSTRAINT payments_entry_check CHECK (
  (status = 'captured' AND amount_cents > 0) OR
  (status = 'reversed' AND amount_cents < 0)
);

-- Include complete before/after row images so Mammoth can emit accurate
-- column-level changes. See ADAPTING.md for the WAL/privacy tradeoff and opt-out.
ALTER TABLE orders REPLICA IDENTITY FULL;

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS orders_set_updated_at ON orders;
CREATE TRIGGER orders_set_updated_at
BEFORE UPDATE ON orders
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

INSERT INTO orders (customer_email, status, total_cents)
SELECT * FROM (VALUES
  ('alice@example.com', 'pending', 4999),
  ('bob@example.com', 'paid', 12900),
  ('carol@example.com', 'shipped', 7599)
) AS seed(customer_email, status, total_cents)
WHERE NOT EXISTS (SELECT 1 FROM orders);

-- Keep seeded or pre-existing paid demo orders consistent with the accounting
-- entry model before offering the reversal action.
INSERT INTO payments (order_id, amount_cents, status)
SELECT orders.id, orders.total_cents, 'captured'
FROM orders
WHERE orders.status = 'paid'
  AND NOT EXISTS (
    SELECT 1
    FROM payments
    WHERE payments.order_id = orders.id
      AND payments.status = 'captured'
  );

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'mammoth_publication') THEN
    CREATE PUBLICATION mammoth_publication FOR TABLE orders, payments;
  END IF;
END
$$;

-- Keep an existing quickstart publication synchronized with the demo schema.
ALTER PUBLICATION mammoth_publication SET TABLE orders, payments;
