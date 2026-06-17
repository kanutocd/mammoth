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
        process_decoded(decoded, metadata, &block)
      end

      def process_decoded(decoded, metadata, &block)
        return if decoded.nil?

        if decoded.is_a?(Array)
          decoded.each { |item| process_decoded(item, metadata, &block) }
          return
        end

        if begin_message?(decoded)
          start_transaction_buffer(decoded)
          return
        end

        if commit_message?(decoded)
          emit_transaction_buffer(decoded, metadata, &block)
          return
        end

        normalize_decoded(decoded).each do |work|
          next unless work

          work = enrich_work_position(work, metadata, decoded)
          if transaction_buffer_active?
            @transaction_events << work
          else
            block.call(work)
          end
        end
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


      def begin_message?(decoded)
        message_kind(decoded).include?("begin")
      end

      def commit_message?(decoded)
        message_kind(decoded).include?("commit")
      end

      def message_kind(decoded)
        (value_from(decoded, :message_type, :type, :kind) || decoded.class.name.to_s.split("::").last).to_s.downcase
      end

      def start_transaction_buffer(decoded)
        @transaction_events = []
        @transaction_id = value_from(decoded, :transaction_id, :xid, :final_lsn)
        @transaction_metadata = value_hash(decoded, :metadata) || {}
      end

      def emit_transaction_buffer(decoded, metadata, &block)
        return unless transaction_buffer_active?

        block.call(
          TransactionEnvelope.new(
            events: @transaction_events,
            transaction_id: transaction_id_for(decoded),
            commit_lsn: commit_lsn_for(decoded, metadata),
            commit_time: value_from(decoded, :commit_time, :committed_at, :timestamp),
            metadata: @transaction_metadata
          )
        )
      ensure
        clear_transaction_buffer
      end

      def transaction_id_for(decoded)
        value_from(decoded, :transaction_id, :xid) || @transaction_id || first_event_value(:transaction_id, :xid)
      end

      def commit_lsn_for(decoded, metadata)
        value_from(decoded, :commit_lsn, :source_position, :lsn, :end_lsn, :final_lsn) ||
          value_from(metadata, :commit_lsn, :source_position, :lsn, :end_lsn, :final_lsn) ||
          first_event_value(:commit_lsn, :source_position, :lsn)
      end

      def transaction_buffer_active?
        !@transaction_events.nil?
      end

      def clear_transaction_buffer
        @transaction_events = nil
        @transaction_id = nil
        @transaction_metadata = nil
      end

      def enrich_work_position(work, metadata, decoded)
        position = value_from(work, :source_position, :commit_lsn) ||
                   value_from(metadata, :source_position, :commit_lsn, :lsn) ||
                   value_from(decoded, :source_position, :commit_lsn, :lsn)
        return work unless position

        work_hash = work.respond_to?(:to_h) ? work.to_h : work
        return work unless work_hash.is_a?(Hash)

        key_style = work_hash.key?("operation") ? :string : :symbol
        source_position_key = key_style == :string ? "source_position" : :source_position
        commit_lsn_key = key_style == :string ? "commit_lsn" : :commit_lsn
        return work if work_hash[source_position_key] || work_hash[commit_lsn_key]

        work_hash.merge(source_position_key => position, commit_lsn_key => position)
      end

      def first_event_value(*keys)
        Array(@transaction_events).find do |event|
          keys.any? { |key| value_from(event, key) }
        end&.then { |event| value_from(event, *keys) }
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

      def value_hash(object, key)
        value = value_from(object, key)
        value.is_a?(Hash) ? value : nil
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
          start_lsn: config.dig("replication", "start_lsn"),
          auto_create_slot: config.dig("replication", "auto_create_slot") == true,
          temporary_slot: config.dig("replication", "temporary_slot") == true
        }.tap do |options|
          feedback_interval = config.dig("replication", "feedback_interval")
          options[:feedback_interval] = feedback_interval unless feedback_interval.nil?
        end
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
      TransactionEnvelope = Data.define(:events, :transaction_id, :commit_lsn, :commit_time, :metadata)
      private_constant :TransactionEnvelope
    end
  end
end
