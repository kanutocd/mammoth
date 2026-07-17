CREATE TABLE IF NOT EXISTS wal_churn (
  id bigserial PRIMARY KEY,
  payload text NOT NULL
);

DO $$
DECLARE
  batch_count integer := 40;
  row_count integer := 40;
BEGIN
  FOR batch_index IN 1..batch_count LOOP
    INSERT INTO wal_churn (payload)
    SELECT repeat(md5(random()::text || clock_timestamp()::text), 64)
    FROM generate_series(1, row_count);
    PERFORM pg_sleep(0.05);
  END LOOP;
END
$$;
