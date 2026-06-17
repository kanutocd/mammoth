CREATE TABLE IF NOT EXISTS orders (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  status text NOT NULL,
  total_cents integer NOT NULL,
  note text
);

CREATE PUBLICATION mammoth_publication FOR TABLE orders;
