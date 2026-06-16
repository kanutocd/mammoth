# frozen_string_literal: true

module Mammoth
  # Streams PostgreSQL logical replication through the CDC Ecosystem boundary.
  #
  # PgoutputSource is Mammoth's upstream integration point. It composes the
  # standalone pgoutput transport, parser, decoder, and source-adapter gems so
  # the rest of Mammoth only receives CDC-core domain objects. Transport
  # resiliency remains owned by pgoutput-client; Mammoth owns delivery.
  class PgoutputSource
    # @return [Mammoth::Configuration] loaded Mammoth configuration
    attr_reader :config
    # @return [Object, nil] pgoutput-client compatible runner
    attr_reader :runner
    # @return [Object, nil] pgoutput-parser compatible parser
    attr_reader :parser
    # @return [Object, nil] pgoutput-decoder compatible decoder
    attr_reader :decoder
    # @return [Object, nil] CDC source adapter
    attr_reader :source_adapter

    # Build the pgoutput integration source.
    #
    # @param config [Mammoth::Configuration] loaded configuration
    # @param runner [Object, nil] injectable pgoutput-client runner
    # @param parser [Object, nil] injectable pgoutput parser
    # @param decoder [Object, nil] injectable pgoutput decoder
    # @param source_adapter [Object, nil] injectable CDC source adapter
    def initialize(config, runner: nil, parser: nil, decoder: nil, source_adapter: nil)
      @config = config
      @runner = runner
      @parser = parser
      @decoder = decoder
      @source_adapter = source_adapter
    end

    # Stream CDC-core objects from PostgreSQL.
    #
    # @yieldparam work [Object] CDC::Core::ChangeEvent or TransactionEnvelope
    # @return [void]
    # @raise [Mammoth::ReplicationError] when required CDC components are unavailable
    def each
      return enum_for(:each) unless block_given?

      effective_runner.start do |payload, metadata|
        normalized_items(payload, metadata).each { |item| yield item }
      end
    end

    private

    def normalized_items(payload, metadata)
      decoded = effective_decoder ? invoke_component(effective_decoder, parsed_payload(payload), metadata) : parsed_payload(payload)
      normalized = invoke_source_adapter(decoded, metadata)
      Array(normalized).flatten
    end

    def parsed_payload(payload)
      return payload unless effective_parser

      invoke_component(effective_parser, payload)
    end

    def invoke_source_adapter(decoded, metadata)
      adapter = effective_source_adapter
      if adapter.respond_to?(:normalize)
        adapter.normalize(decoded)
      elsif adapter.respond_to?(:call)
        adapter.call(decoded, metadata)
      else
        raise ReplicationError, "pgoutput source adapter must respond to #normalize or #call"
      end
    end

    def invoke_component(component, *args)
      if component.respond_to?(:call)
        component.call(*args)
      elsif component.respond_to?(:parse)
        component.parse(*args)
      elsif component.respond_to?(:decode)
        component.decode(*args)
      else
        raise ReplicationError, "#{component.class} must respond to #call, #parse, or #decode"
      end
    end

    def effective_runner
      @runner ||= build_runner
    end

    def effective_parser
      @parser ||= build_parser
    end

    def effective_decoder
      @decoder ||= build_decoder
    end

    def effective_source_adapter
      @source_adapter ||= build_source_adapter
    end

    def build_runner
      require_optional!("pgoutput_client", "pgoutput-client")
      Pgoutput::Client::Runner.new(
        database_url: database_url,
        slot_name: config.dig("replication", "slot"),
        publication_names: [config.dig("replication", "publication")],
        start_lsn: config.dig("replication", "start_lsn"),
        auto_create_slot: config.dig("replication", "auto_create_slot") || false
      )
    end

    def build_parser
      require_any!(["pgoutput_parser", "pgoutput/parser"], "pgoutput-parser")
      constant_or_nil("Pgoutput::Parser") || constant_or_nil("Pgoutput::Parser::Parser")
    end

    def build_decoder
      require_any!(["pgoutput_decoder", "pgoutput/decoder"], "pgoutput-decoder")
      constant_or_nil("Pgoutput::Decoder") || constant_or_nil("Pgoutput::Decoder::ValueDecoder")
    end

    def build_source_adapter
      require_optional!("cdc_core", "cdc-core")
      require_any!(["pgoutput_source_adapter", "pgoutput/source_adapter/cdc"], "pgoutput-source-adapter")

      adapter_class = constant_or_nil("Pgoutput::SourceAdapter::Cdc")
      raise ReplicationError, "Pgoutput::SourceAdapter::Cdc is unavailable" unless adapter_class

      adapter_class.new
    end

    def database_url
      password = ENV.fetch(config.dig("postgres", "password_env"), "")
      user = config.dig("postgres", "username")
      host = config.dig("postgres", "host")
      port = config.dig("postgres", "port")
      database = config.dig("postgres", "database")
      "postgres://#{user}:#{password}@#{host}:#{port}/#{database}"
    end

    def require_optional!(feature, gem_name)
      require feature
    rescue LoadError => e
      raise ReplicationError, "#{gem_name} is required for live pgoutput replication: #{e.message}"
    end

    def require_any!(features, gem_name)
      errors = []
      features.each do |feature|
        require feature
        return true
      rescue LoadError => e
        errors << e.message
      end
      raise ReplicationError, "#{gem_name} is required for live pgoutput replication: #{errors.join("; ")}"
    end

    def constant_or_nil(name)
      name.split("::").reduce(Object) { |scope, const_name| scope.const_get(const_name, false) }
    rescue NameError
      nil
    end
  end
end
