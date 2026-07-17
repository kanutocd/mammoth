# frozen_string_literal: true

require "json"

module Mammoth
  module Sources
    # Immutable replica-identity facts for one table in configured publications.
    class PostgresPublicationTable
      attr_reader :schema_name, :table_name, :publishes_updates, :publishes_deletes, :replica_identity,
                  :primary_key_usable, :replica_identity_index_usable

      # @return [void]
      def initialize(schema_name:, table_name:, publishes_updates:, publishes_deletes:, replica_identity:,
                     primary_key_usable:, replica_identity_index_usable:)
        @schema_name = schema_name
        @table_name = table_name
        @publishes_updates = publishes_updates
        @publishes_deletes = publishes_deletes
        @replica_identity = replica_identity
        @primary_key_usable = primary_key_usable
        @replica_identity_index_usable = replica_identity_index_usable
        freeze
      end

      # Schema-qualified table name for diagnostics.
      #
      # @return [String]
      def qualified_name
        "#{schema_name}.#{table_name}"
      end

      # Publication actions that require old-row identity.
      #
      # @return [Array<String>]
      def identity_actions
        actions = [] # : Array[String]
        actions.tap do
          actions << "UPDATE" if publishes_updates
          actions << "DELETE" if publishes_deletes
        end
      end

      # Whether any configured publication requires replica identity.
      #
      # @return [Boolean]
      def identity_required?
        publishes_updates || publishes_deletes
      end

      # Whether PostgreSQL can identify old rows for the published actions.
      #
      # `d` uses a primary key, `i` uses a selected replica-identity index,
      # and `f` logs the full old row. `n` provides no old-row identity.
      #
      # @return [Boolean]
      def identity_usable?
        return true unless identity_required?

        case replica_identity
        when "d" then primary_key_usable
        when "i" then replica_identity_index_usable
        when "f" then true
        else false
        end
      end
    end

    # Read-only PostgreSQL publication and replica-identity catalog inspector.
    class PostgresPublicationInspector
      QUERY = <<~SQL
        SELECT
          namespace.nspname AS schema_name,
          relation.relname AS table_name,
          bool_or(publication.pubupdate) AS publishes_updates,
          bool_or(publication.pubdelete) AS publishes_deletes,
          relation.relreplident AS replica_identity,
          EXISTS (
            SELECT 1
            FROM pg_index AS primary_index
            WHERE primary_index.indrelid = relation.oid
              AND primary_index.indisprimary
              AND primary_index.indisvalid
              AND primary_index.indisready
              AND primary_index.indislive
          ) AS primary_key_usable,
          EXISTS (
            SELECT 1
            FROM pg_index AS identity_index
            WHERE identity_index.indrelid = relation.oid
              AND identity_index.indisreplident
              AND identity_index.indisvalid
              AND identity_index.indisready
              AND identity_index.indislive
          ) AS replica_identity_index_usable
        FROM pg_publication_tables AS publication_table
        JOIN pg_publication AS publication
          ON publication.pubname = publication_table.pubname
        JOIN pg_namespace AS namespace
          ON namespace.nspname = publication_table.schemaname
        JOIN pg_class AS relation
          ON relation.relnamespace = namespace.oid
         AND relation.relname = publication_table.tablename
        WHERE publication.pubname IN (
          SELECT jsonb_array_elements_text($1::jsonb)
        )
        GROUP BY namespace.nspname, relation.relname, relation.oid, relation.relreplident
        ORDER BY namespace.nspname, relation.relname
      SQL

      attr_reader :database_url

      # @param database_url [String] PostgreSQL connection URL
      # @param connection_factory [#call, nil] optional connection factory for tests
      def initialize(database_url:, connection_factory: nil)
        @database_url = database_url
        @connection_factory = connection_factory
      end

      # Inspect tables included by the configured publications.
      #
      # @param publication_names [Array<String>] configured publication names
      # @return [Array<PostgresPublicationTable>]
      def inspect(publication_names)
        connection = open_connection
        rows = connection.exec_params(QUERY, [JSON.generate(publication_names)])
        rows.map { |row| build_table(row) }
      rescue pg_error_class => e
        raise ReplicationError, "PostgreSQL publication inspection failed: #{e.message}"
      ensure
        connection&.close unless connection&.finished?
      end

      private

      def open_connection
        return @connection_factory.call(database_url) if @connection_factory

        require "pg"
        PG.connect(database_url)
      end

      def build_table(row)
        PostgresPublicationTable.new(
          schema_name: row.fetch("schema_name"),
          table_name: row.fetch("table_name"),
          publishes_updates: postgres_boolean(row.fetch("publishes_updates")),
          publishes_deletes: postgres_boolean(row.fetch("publishes_deletes")),
          replica_identity: row.fetch("replica_identity"),
          primary_key_usable: postgres_boolean(row.fetch("primary_key_usable")),
          replica_identity_index_usable: postgres_boolean(row.fetch("replica_identity_index_usable"))
        )
      end

      def postgres_boolean(value)
        [true, "t"].include?(value)
      end

      def pg_error_class
        require "pg"
        PG::Error
      end
    end
  end
end
