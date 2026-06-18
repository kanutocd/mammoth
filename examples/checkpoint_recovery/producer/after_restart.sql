BEGIN;
INSERT INTO orders (id, order_key, status) VALUES (3, 'C', 'after_restart');
COMMIT;
