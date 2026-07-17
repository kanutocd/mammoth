BEGIN;
INSERT INTO orders (id, order_key, status) VALUES (2, 'B', 'after_recovery');
COMMIT;
