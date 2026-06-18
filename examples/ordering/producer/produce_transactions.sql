BEGIN;
INSERT INTO orders (order_key, status, total_cents) VALUES ('A', 'created', 1000);
COMMIT;

BEGIN;
INSERT INTO orders (order_key, status, total_cents) VALUES ('B', 'created', 2000);
COMMIT;

BEGIN;
INSERT INTO orders (order_key, status, total_cents) VALUES ('C', 'created', 3000);
COMMIT;
