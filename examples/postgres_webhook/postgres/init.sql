CREATE TABLE IF NOT EXISTS orders (
  id bigint PRIMARY KEY,
  status text NOT NULL,
  total_cents integer NOT NULL
);

CREATE PUBLICATION mammoth_publication FOR TABLE orders;
