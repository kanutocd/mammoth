# frozen_string_literal: true

module Mammoth
  # Destination adapter contracts and registry.
  module Destinations
    # Base contract for destination adapters.
    class Adapter
      # @return [Hash] JSON-friendly adapter capabilities
      def self.capabilities
        { type: adapter_type }
      end

      # @return [String] adapter type name
      def self.adapter_type
        type = name.split("::").last.to_s.delete_suffix("Adapter").downcase
        type.empty? ? "adapter" : type
      end
    end
  end
end
