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
      # @return [#inspect, nil] injected PostgreSQL publication inspector
      attr_reader :publication_inspector

      # Build a PostgreSQL CDC source.
      #
      # @param config [Mammoth::Configuration] loaded configuration
      # @param runner [#start, nil] injected pgoutput-client runner
      # @param parser [Object, nil] injected pgoutput parser or relation tracker
      # @param decoder [Object, nil] injected pgoutput decoder
      # @param adapter [Object, nil] injected source adapter
      # @param checkpoint_store [Mammoth::CheckpointStore, nil] persisted checkpoints for restart resume
      # @param publication_inspector [#inspect, nil] injected publication metadata inspector
      def initialize(config, runner: nil, parser: nil, decoder: nil, adapter: nil, checkpoint_store: nil,
                     publication_inspector: nil)
        @config = config
        @runner = runner
        @parser = parser
        @decoder = decoder
        @adapter = adapter
        @checkpoint_store = checkpoint_store
        @publication_inspector = publication_inspector
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

        preflight_slot!
        preflight_replica_identity!
        normalizer = effective_adapter
        unless normalizer.respond_to?(:each_normalized)
          raise ReplicationError, "pgoutput source adapter must respond to #each_normalized"
        end

        normalizer.each_normalized(decoded_stream) do |work|
          yield_with_progress_position(validate_core_work!(work), &block)
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

      # Resolve the acknowledgement-compatible transport position for work
      # currently being yielded by this source.
      #
      # @param work [CDC::Core::ChangeEvent, CDC::Core::TransactionEnvelope] yielded work
      # @return [String, Integer, nil] pgoutput-client compatible WAL position
      def progress_position_for(work)
        return nil unless yielded_work_includes?(work)

        @yielded_progress_position
      end

      # Inspect the configured slot for readiness and operator metrics.
      #
      # pgoutput-client owns catalog access. This method converts its snapshot
      # into Mammoth's PostgreSQL-specific health policy without leaking
      # transport-library types into the observability layer.
      #
      # @return [PostgresSlotHealth]
      def slot_health
        status = inspected_slot_status
        return PostgresSlotHealth.missing(required_config("replication", "slot")) unless status

        PostgresSlotHealth.new(
          slot_name: value_from(status, :slot_name),
          present: true,
          active: value_from(status, :active) == true,
          retained_wal_bytes: value_from(status, :retained_wal_bytes),
          wal_status: value_from(status, :wal_status),
          safe_wal_size: value_from(status, :safe_wal_size),
          inactive_since: value_from(status, :inactive_since),
          invalidation_reason: value_from(status, :invalidation_reason),
          restart_lsn: value_from(status, :restart_lsn),
          restart_lsn_bytes: metric_lsn(value_from(status, :restart_lsn)),
          confirmed_flush_lsn: value_from(status, :confirmed_flush_lsn),
          confirmed_flush_lsn_bytes: metric_lsn(value_from(status, :confirmed_flush_lsn)),
          conflicting: value_from(status, :conflicting) == true
        )
      rescue StandardError => e
        raise e if e.is_a?(ReplicationError)

        raise ReplicationError, "PostgreSQL slot health inspection failed: #{e.message}"
      end

      private

      def decoded_stream
        Enumerator.new do |stream|
          effective_runner.start do |payload, metadata = nil|
            @latest_progress_position = acknowledgement_position(metadata)
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

      def yield_with_progress_position(work)
        @yielded_work = work
        @yielded_progress_position = @latest_progress_position
        yield work
      ensure
        @yielded_work = nil
        @yielded_progress_position = nil
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

      def acknowledgement_position(metadata)
        value = value_from(metadata, :wal_end_lsn, :wal_end, :lsn)
        return nil if value.nil?
        return value if value.is_a?(Integer) && value >= 0
        return value if value.is_a?(String) && value.match?(%r{\A[0-9A-F]+/[0-9A-F]+\z}i)

        raise ReplicationError, "invalid PostgreSQL transport LSN for acknowledgement: #{value.inspect}"
      end

      def yielded_work_includes?(work)
        return true if @yielded_work.equal?(work)
        return false unless @yielded_work.is_a?(CDC::Core::TransactionEnvelope)

        @yielded_work.events.any? { |event| event.equal?(work) }
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

      def effective_publication_inspector
        publication_inspector || @effective_publication_inspector || begin
          @effective_publication_inspector = build_publication_inspector
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

      def build_publication_inspector
        PostgresPublicationInspector.new(database_url:)
      end

      def runner_options
        {
          database_url: database_url,
          slot_name: required_config("replication", "slot"),
          publication_names: required_publications,
          start_lsn: replication_start_lsn,
          auto_create_slot: safe_auto_create_slot?,
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

      def preflight_slot!
        resume_lsn = replication_start_lsn
        validate_temporary_slot_resume!(resume_lsn)
        status = inspected_slot_status

        if status.nil?
          return if safe_auto_create_slot?

          raise ReplicationError, missing_slot_message(resume_lsn)
        end

        validate_slot_identity!(status)
        validate_slot_health!(status)
        validate_slot_reachability!(status, resume_lsn) unless blank?(resume_lsn)
        nil
      rescue StandardError => e
        raise e if e.is_a?(ReplicationError)

        raise ReplicationError, "PostgreSQL slot preflight failed: #{e.message}"
      end

      def preflight_replica_identity!
        invalid_tables = effective_publication_inspector.inspect(required_publications).reject(&:identity_usable?)
        return if invalid_tables.empty?

        details = invalid_tables.map do |table|
          "#{table.qualified_name} (actions=#{table.identity_actions.join("/")}, " \
            "replica_identity=#{replica_identity_name(table.replica_identity)})"
        end
        raise ReplicationError,
              "PostgreSQL replica identity preflight failed for #{details.join(", ")}. " \
              "Add a primary key, select an eligible unique index with REPLICA IDENTITY USING INDEX, " \
              "use REPLICA IDENTITY FULL, or remove UPDATE/DELETE from the publication."
      rescue StandardError => e
        raise e if e.is_a?(ReplicationError)

        raise ReplicationError, "PostgreSQL replica identity preflight failed: #{e.message}"
      end

      def inspected_slot_status
        client = effective_runner
        unless client.respond_to?(:slot_status)
          raise ReplicationError, "pgoutput-client 0.4+ with #slot_status is required for PostgreSQL slot inspection"
        end

        client.slot_status
      end

      def validate_temporary_slot_resume!(resume_lsn)
        return if blank?(resume_lsn)
        return unless config.dig("replication", "temporary_slot") == true

        raise ReplicationError, "cannot resume durable PostgreSQL checkpoint #{resume_lsn} with a temporary slot"
      end

      def validate_slot_identity!(status)
        slot_name = required_config("replication", "slot")
        unless value_from(status, :slot_name) == slot_name
          raise ReplicationError, "PostgreSQL slot preflight returned the wrong slot for #{slot_name}"
        end
        unless value_from(status, :slot_type) == "logical" && value_from(status, :plugin) == "pgoutput"
          raise ReplicationError, "PostgreSQL slot #{slot_name} must be a logical pgoutput slot"
        end

        database = required_config("postgres", "database")
        return if value_from(status, :database) == database

        raise ReplicationError, "PostgreSQL slot #{slot_name} belongs to a different database"
      end

      def validate_slot_health!(status)
        slot_name = required_config("replication", "slot")
        raise ReplicationError, "PostgreSQL slot #{slot_name} is already active" if value_from(status, :active) == true

        wal_status = value_from(status, :wal_status)
        if %w[lost unreserved].include?(wal_status)
          raise ReplicationError, "PostgreSQL slot #{slot_name} cannot retain required WAL (wal_status=#{wal_status})"
        end

        invalidation_reason = value_from(status, :invalidation_reason)
        if value_from(status, :conflicting) == true || !blank?(invalidation_reason)
          raise ReplicationError,
                "PostgreSQL slot #{slot_name} is invalidated#{": #{invalidation_reason}" unless blank?(invalidation_reason)}"
        end

        return unless blank?(value_from(status, :restart_lsn))

        raise ReplicationError, "PostgreSQL slot #{slot_name} has no reachable restart LSN"
      end

      def validate_slot_reachability!(status, resume_lsn)
        requested = parse_transport_lsn(resume_lsn, "resume checkpoint")
        %i[restart_lsn confirmed_flush_lsn].each do |field|
          boundary = value_from(status, field)
          next if blank?(boundary)
          next unless requested < parse_transport_lsn(boundary, field.to_s)

          raise ReplicationError,
                "PostgreSQL slot cannot serve checkpoint #{resume_lsn}; #{field}=#{boundary} has already advanced past it"
        end
      end

      def parse_transport_lsn(value, label)
        require_optional!("pgoutput/client", "pgoutput-client")
        Pgoutput::Client::LSN.parse(value)
      rescue StandardError => e
        raise ReplicationError, "invalid PostgreSQL #{label} LSN #{value.inspect}: #{e.message}"
      end

      def metric_lsn(value)
        return nil if blank?(value)

        parse_transport_lsn(value, "slot metric")
      end

      def replica_identity_name(value)
        {
          "d" => "default",
          "n" => "nothing",
          "f" => "full",
          "i" => "index"
        }.fetch(value, value)
      end

      def safe_auto_create_slot?
        config.dig("replication", "auto_create_slot") == true && blank?(replication_start_lsn)
      end

      def missing_slot_message(resume_lsn)
        slot_name = required_config("replication", "slot")
        return "PostgreSQL slot #{slot_name} is missing and auto_create_slot is disabled" if blank?(resume_lsn)

        "PostgreSQL slot #{slot_name} is missing; refusing to recreate it while checkpoint #{resume_lsn} requires continuity"
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
