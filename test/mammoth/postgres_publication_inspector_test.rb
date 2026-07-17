# frozen_string_literal: true

require "test_helper"

module Mammoth
  module Sources
    class PostgresPublicationInspectorTest < Minitest::Test
      class FakeConnection
        attr_reader :queries

        def initialize(rows: [], error: nil, finished: false)
          @rows = rows
          @error = error
          @finished = finished
          @queries = []
        end

        def exec_params(sql, parameters)
          raise @error if @error

          queries << [sql, parameters]
          @rows
        end

        def finished? = @finished
        def close = @closed = true
        def closed? = @closed
      end

      def test_inspects_and_normalizes_publication_table_identity
        connection = FakeConnection.new(rows: [{
                                          "schema_name" => "public",
                                          "table_name" => "orders",
                                          "publishes_updates" => "t",
                                          "publishes_deletes" => false,
                                          "replica_identity" => "d",
                                          "primary_key_usable" => true,
                                          "replica_identity_index_usable" => "f"
                                        }])

        tables = inspector(connection).inspect(%w[orders_publication audit_publication])

        table = tables.fetch(0)
        assert_equal "public.orders", table.qualified_name
        assert_equal ["UPDATE"], table.identity_actions
        assert_predicate table, :identity_required?
        assert_predicate table, :identity_usable?
        assert_equal [JSON.generate(%w[orders_publication audit_publication])],
                     connection.queries.fetch(0).fetch(1)
        assert_predicate connection, :closed?
      end

      def test_query_aggregates_publication_actions_and_checks_usable_indexes
        query = PostgresPublicationInspector::QUERY

        assert_match(/bool_or\(publication\.pubupdate\)/, query)
        assert_match(/bool_or\(publication\.pubdelete\)/, query)
        assert_match(/primary_index\.indisprimary/, query)
        assert_match(/identity_index\.indisreplident/, query)
        assert_match(/indisvalid/, query)
        assert_match(/jsonb_array_elements_text/, query)
      end

      def test_wraps_pg_errors_and_closes_connection
        require "pg"
        connection = FakeConnection.new(error: PG::Error.new("catalog unavailable"))

        error = assert_raises(ReplicationError) { inspector(connection).inspect(["orders_publication"]) }

        assert_match(/publication inspection failed: catalog unavailable/, error.message)
        assert_predicate connection, :closed?
      end

      def test_does_not_close_finished_connection
        connection = FakeConnection.new(finished: true)

        inspector(connection).inspect(["orders_publication"])

        refute_predicate connection, :closed?
      end

      def test_opens_default_pg_connection
        require "pg"
        connection = FakeConnection.new

        connector = lambda do |database_url|
          assert_equal "postgres://localhost/app", database_url
          connection
        end
        PG.stub(:connect, connector) do
          tables = PostgresPublicationInspector.new(
            database_url: "postgres://localhost/app"
          ).inspect(["orders_publication"])

          assert_empty tables
        end
        assert_predicate connection, :closed?
      end

      def test_wraps_default_connection_open_errors
        require "pg"

        PG.stub(:connect, ->(_database_url) { raise PG::Error, "connection unavailable" }) do
          error = assert_raises(ReplicationError) do
            PostgresPublicationInspector.new(
              database_url: "postgres://localhost/app"
            ).inspect(["orders_publication"])
          end

          assert_match(/publication inspection failed: connection unavailable/, error.message)
        end
      end

      private

      def inspector(connection)
        PostgresPublicationInspector.new(
          database_url: "postgres://localhost/app",
          connection_factory: ->(_database_url) { connection }
        )
      end
    end

    class PostgresPublicationTableTest < Minitest::Test
      def test_accepts_supported_replica_identity_modes
        assert_predicate table(replica_identity: "d", primary_key_usable: true), :identity_usable?
        assert_predicate table(replica_identity: "i", replica_identity_index_usable: true), :identity_usable?
        assert_predicate table(replica_identity: "f"), :identity_usable?
      end

      def test_rejects_missing_or_unusable_replica_identity
        refute_predicate table(replica_identity: "d"), :identity_usable?
        refute_predicate table(replica_identity: "i"), :identity_usable?
        refute_predicate table(replica_identity: "n"), :identity_usable?
      end

      def test_allows_insert_only_publication_without_identity
        publication_table = table(
          replica_identity: "n",
          publishes_updates: false,
          publishes_deletes: false
        )

        refute_predicate publication_table, :identity_required?
        assert_predicate publication_table, :identity_usable?
        assert_empty publication_table.identity_actions
      end

      private

      def table(**overrides)
        PostgresPublicationTable.new(
          schema_name: "public",
          table_name: "orders",
          publishes_updates: true,
          publishes_deletes: true,
          replica_identity: "d",
          primary_key_usable: false,
          replica_identity_index_usable: false,
          **overrides
        )
      end
    end
  end
end
