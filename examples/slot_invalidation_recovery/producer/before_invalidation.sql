BEGIN;
INSERT INTO orders (id, order_key, status) VALUES (1, 'A', 'before_invalidation');
COMMIT;
