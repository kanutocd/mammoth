# frozen_string_literal: true

module Mammoth
  # Namespace for Mammoth source adapters.
  module Sources
    # Concrete PostgreSQL CDC source for Mammoth.
    #
    # Postgres realizes the CDC Ecosystem libraries for Mammoth's product
    # boundary. It composes pgoutput-client, pgoutput-parser,
    # pgoutput-decoder, and pgoutput-source-adapter into a single source that
    # yields CDC::Core work to the delivery runtime.
    #
    # This class may mention pgoutput implementation details because it is the
    # concrete PostgreSQL source adapter used by Mammoth. The rest of Mammoth
    # should remain source-agnostic and consume only the work yielded here.
    # rubocop:disable Metrics/ClassLength
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
      # @return [Mammoth::CheckpointStore, nil] checkpoint store used for restart resume
      attr_reader :checkpoint_store

      # Build a PostgreSQL CDC source.
      #
      # @param config [Mammoth::Configuration] loaded configuration
      # @param runner [#start, nil] injected pgoutput-client runner
      # @param parser [Object, nil] injected pgoutput parser or relation tracker
      # @param decoder [Object, nil] injected pgoutput decoder
      # @param adapter [Object, nil] injected source adapter
      # @param checkpoint_store [Mammoth::CheckpointStore, nil] persisted checkpoints for restart resume
      def initialize(config, runner: nil, parser: nil, decoder: nil, adapter: nil, checkpoint_store: nil)
        @config = config
        @runner = runner
        @parser = parser
        @decoder = decoder
        @adapter = adapter
        @checkpoint_store = checkpoint_store
      end

      # Stream CDC::Core work from PostgreSQL logical replication.
      #
      # Calling this method starts the injected or configured pgoutput-client
      # runner. The runner owns the PostgreSQL replication connection and slot
      # lifecycle, while pgoutput-source-adapter owns transaction buffering and
      # normalization into CDC::Core work items. This class only composes those
      # layers and forwards transport source positions to the adapter.
      #
      # @yieldparam work [CDC::Core::ChangeEvent, CDC::Core::TransactionEnvelope]
      # @return [Enumerator, nil]
      # @raise [Mammoth::ReplicationError] when the source cannot stream CDC work
      def each(&block)
        return enum_for(:each) unless block_given?

        normalizer = effective_adapter
        unless normalizer.respond_to?(:each_normalized)
          raise ReplicationError, "pgoutput source adapter must respond to #each_normalized"
        end

        normalizer.each_normalized(decoded_stream) do |work|
          block.call(validate_core_work!(work))
        end
        nil
      rescue StandardError => e
        raise e if e.is_a?(ReplicationError)

        raise ReplicationError, "PostgreSQL CDC source failed: #{e.message}"
      end

      # Acknowledge a durably handled PostgreSQL WAL position.
      #
      # @param lsn [String, Integer] pgoutput-client compatible WAL position
      # @return [Integer] normalized acknowledged WAL position
      def acknowledge(lsn)
        effective_runner.ack(lsn)
      rescue StandardError => e
        raise ReplicationError, "PostgreSQL WAL acknowledgement failed: #{e.message}"
      end

      private

      def decoded_stream
        Enumerator.new do |stream|
          effective_runner.start do |payload, metadata = nil|
            process_payload(payload, metadata) { |decoded| stream << stream_event(decoded, metadata) }
          end
        end
      end

      def process_payload(payload, metadata, &block)
        parsed = parse_payload(payload)
        decoded = decode_message(parsed, metadata)
        each_decoded(decoded, &block)
      end

      def each_decoded(decoded, &block)
        return if decoded.nil?

        if decoded.is_a?(Array)
          decoded.each { |item| each_decoded(item, &block) }
          return
        end

        block.call(decoded)
      end

      def stream_event(decoded, metadata)
        normalizer = effective_adapter
        return decoded unless normalizer.respond_to?(:stream_event)

        normalizer.stream_event(decoded, source_position: source_position(metadata))
      end

      def validate_core_work!(work)
        return work if work.is_a?(CDC::Core::ChangeEvent)
        return work if work.is_a?(CDC::Core::TransactionEnvelope)

        raise ReplicationError, "pgoutput source adapter yielded non-core work: #{work.class}"
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

      def value_from(object, *keys)
        return nil if object.nil?

        keys.each do |key|
          return object.public_send(key) if object.respond_to?(key)

          hash = object.respond_to?(:to_h) ? object.to_h : object
          next unless hash.respond_to?(:key?)

          return hash[key] if hash.key?(key)
          return hash[key.to_s] if hash.key?(key.to_s)
        end

        nil
      end

      def source_position(metadata)
        value_from(metadata, :source_position, :commit_lsn, :lsn, :wal_end_lsn, :end_lsn, :final_lsn)
      end

      def effective_runner
        runner || @effective_runner || begin
          @effective_runner = build_runner
        end
      end

      def effective_parser
        parser || @effective_parser || begin
          @effective_parser = build_parser
        end
      end

      def effective_decoder
        decoder || @effective_decoder || begin
          @effective_decoder = build_decoder
        end
      end

      def effective_adapter
        adapter || @effective_adapter || begin
          @effective_adapter = build_adapter
        end
      end

      def build_runner
        require_optional!("pgoutput/client", "pgoutput-client")

        Pgoutput::Client::Runner.new(**runner_options)
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

      def runner_options
        {
          database_url: database_url,
          slot_name: required_config("replication", "slot"),
          publication_names: required_publications,
          start_lsn: replication_start_lsn,
          auto_create_slot: config.dig("replication", "auto_create_slot") == true,
          temporary_slot: config.dig("replication", "temporary_slot") == true
        }.tap do |options|
          feedback_interval = config.dig("replication", "feedback_interval")
          options[:feedback_interval] = feedback_interval unless feedback_interval.nil?
        end
      end

      def replication_start_lsn
        configured = config.dig("replication", "start_lsn")
        return configured unless blank?(configured)

        checkpoint_lsn
      end

      def checkpoint_lsn
        return nil unless checkpoint_store

        row = checkpoint_store.fetch(source_name: source_name, slot_name: required_config("replication", "slot"))
        normalize_lsn(row&.fetch("last_lsn", nil))
      end

      def source_name
        required_config("mammoth", "name")
      end

      def normalize_lsn(value)
        return nil if blank?(value)

        lsn = value.to_s
        return lsn if lsn.include?("/")
        return "0/#{lsn.to_i.to_s(16).upcase}" if lsn.match?(/\A\d+\z/)

        lsn
      end

      def blank?(value)
        value.nil? || value == ""
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
    # rubocop:enable Metrics/ClassLength
  end
end
