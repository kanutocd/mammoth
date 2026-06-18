BEGIN;
INSERT INTO orders (id, order_key, status) VALUES (1, 'A', 'before_restart');
COMMIT;

BEGIN;
INSERT INTO orders (id, order_key, status) VALUES (2, 'B', 'before_restart');
COMMIT;
