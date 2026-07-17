\pset pager off
\echo 'Replication slot'
SELECT
  slot_name,
  plugin,
  slot_type,
  active,
  restart_lsn,
  confirmed_flush_lsn,
  wal_status,
  safe_wal_size,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal
FROM pg_replication_slots
WHERE slot_name = 'mammoth_postgres_observability';

\echo 'Replication sender'
SELECT
  application_name,
  state,
  sent_lsn,
  write_lsn,
  flush_lsn,
  replay_lsn,
  write_lag,
  flush_lag,
  replay_lag
FROM pg_stat_replication;

\echo 'Publication tables'
SELECT pubname, schemaname, tablename
FROM pg_publication_tables
WHERE pubname = 'mammoth_publication'
ORDER BY schemaname, tablename;
