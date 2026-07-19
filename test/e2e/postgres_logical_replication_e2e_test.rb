# frozen_string_literal: true

require "test_helper"
require "pg"
require "timeout"
require "uri"
require "yaml"

module Mammoth
  # rubocop:disable Metrics/AbcSize, Metrics/BlockLength, Metrics/ClassLength
  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  class PostgresLogicalReplicationE2ETest < Minitest::Test
    E2E_DATABASE_URL = "MAMMOTH_E2E_POSTGRES_URL"
    PASSWORD_ENV = "MAMMOTH_E2E_POSTGRES_PASSWORD"
    STREAM_TIMEOUT = 20

    Fixture = Data.define(:connection, :schema_name, :table_name, :publication_name, :slot_name, :config)

    def setup
      super
      skip "set #{E2E_DATABASE_URL} to run real PostgreSQL logical-replication tests" unless postgres_url
    end

    def test_streams_insert_update_delete_with_composite_identity
      with_postgres_fixture do |fixture|
        source = Sources::Postgres.new(fixture.config)
        works = stream_work(
          source,
          expected: 1,
          produce: -> { execute_composite_transaction(fixture) }
        )

        envelope = works.fetch(0).fetch(0)
        assert_equal %i[insert update delete], envelope.events.map(&:operation)
        envelope.events.each do |event|
          assert_equal(
            { "tenant_id" => 9, "member_uuid" => "member-1" },
            event.primary_key,
            "unexpected #{event.operation} replica identity"
          )
        end
        assert_equal "created", envelope.events.fetch(0).new_values.fetch("status")
        assert_equal "paid", envelope.events.fetch(1).new_values.fetch("status")
        assert_nil envelope.events.fetch(2).new_values
      end
    end

    def test_reconnects_after_real_replication_connection_termination
      with_postgres_fixture do |fixture|
        source = Sources::Postgres.new(fixture.config)
        runner = source.send(:effective_runner)
        works = stream_work(
          source,
          expected: 1,
          produce: lambda {
            terminate_replication_backend(fixture)
            wait_until { runner.monitor.reconnect_attempts.positive? && runner.connected? }
            insert_membership(fixture, member_uuid: "after-reconnect")
          }
        )

        event = works.fetch(0).fetch(0).events.fetch(0)
        assert_equal "after-reconnect", event.new_values.fetch("member_uuid")
        assert_operator runner.monitor.reconnect_attempts, :>=, 1
      end
    end

    def test_out_of_order_completion_advances_checkpoint_and_slot_acknowledgement_contiguously
      with_postgres_fixture do |fixture|
        with_temp_dir do |dir|
          checkpoint_store = CheckpointStore.new(
            SQLiteStore.connect(File.join(dir, "mammoth.db")).bootstrap!
          )
          source = Sources::Postgres.new(fixture.config, checkpoint_store: checkpoint_store)
          coordinator = DeliveryProgressCoordinator.new(
            checkpoint_store: checkpoint_store,
            source_name: "postgres_e2e",
            slot_name: fixture.slot_name,
            publication_name: fixture.publication_name,
            acknowledger: source.method(:acknowledge),
            position_resolver: source.method(:progress_position_for)
          )
          registered = []

          works = stream_work(
            source,
            expected: 2,
            produce: -> { insert_two_transactions(fixture) },
            on_work: lambda { |work|
              coordinator.register(work, group_end: true)
              registered << work
              next unless registered.length == 2

              assert_nil coordinator.complete(registered.fetch(1))
              assert_nil checkpoint_store.fetch(source_name: "postgres_e2e", slot_name: fixture.slot_name)
              coordinator.complete(registered.fetch(0))
            }
          )

          final_position = works.fetch(1).fetch(1)
          checkpoint = checkpoint_store.fetch(source_name: "postgres_e2e", slot_name: fixture.slot_name)
          assert_equal final_position, checkpoint.fetch("last_lsn")
          wait_until { slot_confirmed_flush_lsn(fixture) == final_position }
          assert_equal final_position, slot_confirmed_flush_lsn(fixture)
        end
      end
    end

    def test_fails_closed_after_postgresql_invalidates_slot
      with_postgres_fixture do |fixture|
        original_limit = fixture.connection.exec("SHOW max_slot_wal_keep_size").getvalue(0, 0)
        begin
          set_max_slot_wal_keep_size(fixture.connection, "1MB")
          force_slot_wal_loss(fixture)

          status = slot_status(fixture)
          assert_equal "lost", status.fetch("wal_status")
          assert_equal "wal_removed", status["invalidation_reason"] if status.key?("invalidation_reason")

          error = assert_raises(ReplicationError) { Sources::Postgres.new(fixture.config).each.to_a }
          assert_match(/cannot retain required WAL.*wal_status=lost/, error.message)
        ensure
          set_max_slot_wal_keep_size(fixture.connection, original_limit)
        end
      end
    end

    private

    def postgres_url
      ENV[E2E_DATABASE_URL]
    end

    def with_postgres_fixture
      uri = URI.parse(postgres_url)
      previous_password = ENV[PASSWORD_ENV]
      ENV[PASSWORD_ENV] = URI.decode_www_form_component(uri.password.to_s)
      connection = connect_postgres
      suffix = "#{Process.pid}_#{rand(1_000_000)}"
      schema_name = "mammoth_e2e_#{suffix}"
      table_name = "memberships"
      publication_name = "mammoth_pub_#{suffix}"
      slot_name = "mammoth_slot_#{suffix}"

      create_replication_objects(connection, schema_name, table_name, publication_name, slot_name)
      config = postgres_config(uri, publication_name, slot_name)
      yield Fixture.new(connection, schema_name, table_name, publication_name, slot_name, config)
    ensure
      cleanup_replication_objects(connection, schema_name, publication_name, slot_name) if connection
      connection&.close unless connection&.finished?
      ENV[PASSWORD_ENV] = previous_password
    end

    def connect_postgres
      Timeout.timeout(STREAM_TIMEOUT) do
        loop do
          return PG.connect(postgres_url)
        rescue PG::Error
          sleep 0.1
        end
      end
    end

    def create_replication_objects(connection, schema_name, table_name, publication_name, slot_name)
      table = qualified_table(connection, schema_name, table_name)
      connection.exec("CREATE SCHEMA #{connection.quote_ident(schema_name)}")
      connection.exec(<<~SQL)
        CREATE TABLE #{table} (
          tenant_id bigint NOT NULL,
          member_uuid text NOT NULL,
          status text NOT NULL,
          PRIMARY KEY (tenant_id, member_uuid)
        )
      SQL
      connection.exec("CREATE TABLE #{connection.quote_ident(schema_name)}.wal_pressure (payload text NOT NULL)")
      connection.exec("CREATE PUBLICATION #{connection.quote_ident(publication_name)} FOR TABLE #{table}")
      connection.exec_params("SELECT pg_create_logical_replication_slot($1, 'pgoutput')", [slot_name])
    end

    def cleanup_replication_objects(connection, schema_name, publication_name, slot_name)
      terminate_slot_backend(connection, slot_name)
      connection.exec_params(
        "SELECT pg_drop_replication_slot(slot_name) FROM pg_replication_slots WHERE slot_name = $1",
        [slot_name]
      )
      connection.exec("DROP PUBLICATION IF EXISTS #{connection.quote_ident(publication_name)}")
      connection.exec("DROP SCHEMA IF EXISTS #{connection.quote_ident(schema_name)} CASCADE")
    rescue PG::Error
      nil
    end

    def postgres_config(uri, publication_name, slot_name)
      data = YAML.safe_load(minimal_config, aliases: false)
      data["mammoth"]["name"] = "postgres_e2e"
      data["postgres"] = {
        "host" => uri.host,
        "port" => uri.port,
        "database" => uri.path.delete_prefix("/"),
        "username" => URI.decode_www_form_component(uri.user.to_s),
        "password_env" => PASSWORD_ENV
      }
      data["replication"] = {
        "slot" => slot_name,
        "publications" => [publication_name],
        "auto_create_slot" => false,
        "temporary_slot" => false,
        "feedback_interval" => 0.05
      }
      Configuration.from_hash(data)
    end

    def stream_work(source, expected:, produce:, on_work: nil)
      runner = source.send(:effective_runner)
      works = []
      errors = Queue.new
      thread = Thread.new do
        source.each do |work|
          works << [work, source.progress_position_for(work)]
          on_work&.call(work)
          runner.stop if works.length >= expected
        end
      rescue StandardError => e
        errors << e
      end

      wait_until { runner.connected? || !errors.empty? }
      raise errors.pop unless errors.empty?

      produce.call
      Timeout.timeout(STREAM_TIMEOUT) { thread.join until !thread.alive? || !errors.empty? }
      raise errors.pop unless errors.empty?
      raise "replication stream did not stop" if thread.alive?

      assert_equal expected, works.length
      works
    ensure
      runner&.stop
      thread&.join(2)
    end

    def execute_composite_transaction(fixture)
      table = qualified_table(fixture.connection, fixture.schema_name, fixture.table_name)
      fixture.connection.exec(<<~SQL)
        BEGIN;
        INSERT INTO #{table} (tenant_id, member_uuid, status) VALUES (9, 'member-1', 'created');
        UPDATE #{table} SET status = 'paid' WHERE tenant_id = 9 AND member_uuid = 'member-1';
        DELETE FROM #{table} WHERE tenant_id = 9 AND member_uuid = 'member-1';
        COMMIT;
      SQL
    end

    def insert_two_transactions(fixture)
      insert_membership(fixture, member_uuid: "first")
      insert_membership(fixture, member_uuid: "second")
    end

    def insert_membership(fixture, member_uuid:)
      table = qualified_table(fixture.connection, fixture.schema_name, fixture.table_name)
      fixture.connection.exec_params(
        "INSERT INTO #{table} (tenant_id, member_uuid, status) VALUES ($1, $2, $3)",
        [9, member_uuid, "created"]
      )
    end

    def terminate_replication_backend(fixture)
      wait_until { slot_status(fixture)["active_pid"] }
      terminate_slot_backend(fixture.connection, fixture.slot_name)
    end

    def terminate_slot_backend(connection, slot_name)
      connection.exec_params(
        <<~SQL,
          SELECT pg_terminate_backend(active_pid)
          FROM pg_replication_slots
          WHERE slot_name = $1
            AND active_pid IS NOT NULL
        SQL
        [slot_name]
      )
    end

    def set_max_slot_wal_keep_size(connection, value)
      connection.exec("ALTER SYSTEM SET max_slot_wal_keep_size = #{connection.escape_literal(value)}")
      connection.exec("SELECT pg_reload_conf()")
      wait_until { connection.exec("SHOW max_slot_wal_keep_size").getvalue(0, 0) == value }
    end

    def force_slot_wal_loss(fixture)
      pressure_table = "#{fixture.connection.quote_ident(fixture.schema_name)}.wal_pressure"
      4.times do
        fixture.connection.exec(<<~SQL)
          INSERT INTO #{pressure_table} (payload)
          SELECT repeat(md5(random()::text || value::text), 20)
          FROM generate_series(1, 25000) AS value;
          SELECT pg_switch_wal();
          CHECKPOINT;
        SQL
        return if slot_status(fixture)["wal_status"] == "lost"
      end
      raise "PostgreSQL did not invalidate the test replication slot"
    end

    def slot_confirmed_flush_lsn(fixture)
      slot_status(fixture)["confirmed_flush_lsn"]
    end

    def slot_status(fixture)
      columns = %w[slot_name active active_pid confirmed_flush_lsn wal_status]
      columns << "invalidation_reason" if server_version(fixture.connection) >= 17
      result = fixture.connection.exec_params(
        "SELECT #{columns.join(", ")} FROM pg_replication_slots WHERE slot_name = $1",
        [fixture.slot_name]
      )
      result.ntuples.zero? ? {} : result[0]
    end

    def server_version(connection)
      connection.server_version / 10_000
    end

    def qualified_table(connection, schema_name, table_name)
      "#{connection.quote_ident(schema_name)}.#{connection.quote_ident(table_name)}"
    end

    def wait_until
      Timeout.timeout(STREAM_TIMEOUT) do
        loop do
          return true if yield

          sleep 0.05
        end
      end
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/BlockLength, Metrics/ClassLength
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
end
