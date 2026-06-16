# frozen_string_literal: true

module Mammoth
  module Sources
    # Concrete PostgreSQL CDC source for Mammoth.
    #
    # Postgres realizes the CDC Ecosystem libraries for Mammoth's product
    # boundary. It composes pgoutput-client, pgoutput-parser,
    # pgoutput-decoder, and pgoutput-source-adapter into a single source that
    # yields CDC::Core-shaped work to the delivery runtime.
    #
    # This class may mention pgoutput implementation details because it is the
    # concrete PostgreSQL source adapter used by Mammoth. The rest of Mammoth
    # should remain source-agnostic and consume only the work yielded here.
    class Postgres
      # @return [Mammoth::Configuration] loaded Mammoth configuration
      attr_reader :config
      # @return [#start, nil] injected pgoutput-client runner
      attr_reader :runner
      # @return [Object, nil] injected pgoutput protocol parser
      attr_reader :parser
      # @return [Object, nil] injected pgoutput decoder
      attr_reader :decoder
      # @return [Object, nil] injected CDC source adapter
      attr_reader :adapter

      # Build a PostgreSQL CDC source.
      #
      # @param config [Mammoth::Configuration] loaded configuration
      # @param runner [#start, nil] injected pgoutput-client runner
      # @param parser [Object, nil] injected pgoutput parser or relation tracker
      # @param decoder [Object, nil] injected pgoutput decoder
      # @param adapter [Object, nil] injected source adapter
      def initialize(config, runner: nil, parser: nil, decoder: nil, adapter: nil)
        @config = config
        @runner = runner
        @parser = parser
        @decoder = decoder
        @adapter = adapter
      end

      # Stream CDC::Core-shaped work from PostgreSQL logical replication.
      #
      # Calling this method starts the injected or configured pgoutput-client
      # runner. The runner owns the PostgreSQL replication connection and slot
      # lifecycle; this class only composes the parser, decoder, and adapter
      # libraries around the stream.
      #
      # @yieldparam work [Object] CDC::Core::ChangeEvent or TransactionEnvelope
      # @return [Enumerator, nil]
      # @raise [Mammoth::ReplicationError] when the source cannot stream CDC work
      def each(&block)
        return enum_for(:each) unless block_given?

        effective_runner.start do |payload, metadata = nil|
          process_payload(payload, metadata, &block)
        end
        nil
      rescue StandardError => e
        raise e if e.is_a?(ReplicationError)

        raise ReplicationError, "PostgreSQL CDC source failed: #{e.message}"
      end

      private

      def process_payload(payload, metadata, &block)
        parsed = parse_payload(payload)
        decoded = decode_message(parsed, metadata)
        normalize_decoded(decoded).each { |work| block.call(work) if work }
      end

      def parse_payload(payload)
        parser = effective_parser
        return parser.process(payload) if parser.respond_to?(:process)
        return parser.parse(payload) if parser.respond_to?(:parse)
        return parser.call(payload) if parser.respond_to?(:call)

        raise ReplicationError, "pgoutput parser must respond to #process, #parse, or #call"
      end

      def decode_message(message, metadata)
        decoder = effective_decoder
        if decoder.respond_to?(:decode)
          return callable_accepts_metadata?(decoder, :decode) ? decoder.decode(message, metadata) : decoder.decode(message)
        end
        if decoder.respond_to?(:call)
          return callable_accepts_metadata?(decoder, :call) ? decoder.call(message, metadata) : decoder.call(message)
        end

        raise ReplicationError, "pgoutput decoder must respond to #decode or #call"
      end

      def normalize_decoded(decoded)
        return [] if decoded.nil?
        return decoded.flat_map { |item| normalize_decoded(item) } if decoded.is_a?(Array)

        adapter = effective_adapter
        result = if adapter.respond_to?(:normalize)
                   adapter.normalize(decoded)
                 elsif adapter.respond_to?(:call)
                   adapter.call(decoded)
                 else
                   raise ReplicationError, "pgoutput source adapter must respond to #normalize or #call"
                 end

        result.is_a?(Array) ? result.compact : [result].compact
      end

      def effective_runner
        runner || (@effective_runner ||= build_runner)
      end

      def effective_parser
        parser || (@effective_parser ||= build_parser)
      end

      def effective_decoder
        decoder || (@effective_decoder ||= build_decoder)
      end

      def effective_adapter
        adapter || (@effective_adapter ||= build_adapter)
      end

      def build_runner
        require_optional!("pgoutput/client", "pgoutput-client")

        Pgoutput::Client::Runner.new(
          database_url: database_url,
          slot_name: required_config("replication", "slot"),
          publication_names: required_publications,
          start_lsn: config.dig("replication", "start_lsn"),
          auto_create_slot: !!config.dig("replication", "auto_create_slot")
        )
      end

      def build_parser
        require_optional!("pgoutput", "pgoutput-parser")

        Pgoutput::RelationTracker.new
      end

      def build_decoder
        require_optional!("pgoutput/decoder", "pgoutput-decoder")

        Pgoutput::Decoder.new
      end

      def build_adapter
        require_optional!("pgoutput/source_adapter", "pgoutput-source-adapter")

        Pgoutput::SourceAdapter::Cdc.new
      end

      def required_publications
        publications = required_config("replication", "publications")
        unless publications.is_a?(Array) && publications.any? &&
               publications.all? { |publication| publication.is_a?(String) && !publication.empty? }
          raise ReplicationError, "missing PostgreSQL source config: replication.publications"
        end

        publications
      end

      def callable_accepts_metadata?(object, method_name)
        arity = object.respond_to?(:arity) && method_name == :call ? object.arity : object.method(method_name).arity
        arity != 1
      end

      def database_url
        password = ENV.fetch(required_config("postgres", "password_env"), nil)
        credentials = required_config("postgres", "username").dup
        credentials << ":#{password}" if password

        "postgres://#{credentials}@#{required_config("postgres", "host")}:#{required_config("postgres", "port")}/" \
          "#{required_config("postgres", "database")}"
      end

      def required_config(*keys)
        value = config.dig(*keys)
        raise ReplicationError, "missing PostgreSQL source config: #{keys.join(".")}" if value.nil? || value == ""

        value
      end

      def require_optional!(feature, gem_name)
        require feature
        true
      rescue LoadError => e
        raise ReplicationError, "#{gem_name} is required for PostgreSQL CDC source integration: #{e.message}"
      end
    end
  end
end
