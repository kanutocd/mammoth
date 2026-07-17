CREATE TABLE orders (
  id integer PRIMARY KEY,
  order_key text NOT NULL UNIQUE,
  status text NOT NULL DEFAULT 'created',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE PUBLICATION mammoth_publication FOR TABLE orders;
