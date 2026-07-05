# frozen_string_literal: true

require "test_helper"

module Mammoth
  class NodeIdentityTest < Minitest::Test
    def test_reads_configured_identity
      with_temp_dir do |dir|
        config = Configuration.load(write_file(File.join(dir, "mammoth.yml"), config_with_node(File.join(dir, "mammoth.db"))))
        identity = NodeIdentity.from_config(config)

        assert_equal "node-1", identity.node_id
        assert_equal "primary-node", identity.node_name
        assert_equal "fleet-a", identity.fleet_id
        assert_equal "production", identity.environment
        assert_equal({ "region" => "ap-southeast-1" }, identity.labels)
        assert_equal "node-1", identity.to_h.fetch(:node_id)
      end
    end

    def test_defaults_identity_from_host_and_mammoth_name
      with_temp_dir do |dir|
        config = Configuration.load(
          write_file(File.join(dir, "mammoth.yml"), minimal_config(sqlite_path: File.join(dir, "mammoth.db")))
        )
        identity = NodeIdentity.from_config(config)

        refute_empty identity.node_id
        assert_equal "local_mammoth", identity.node_name
        assert_nil identity.fleet_id
      end
    end

    private

    def config_with_node(sqlite_path)
      minimal_config(sqlite_path: sqlite_path).sub("postgres:", <<~YAML)
        node:
          node_id: node-1
          node_name: primary-node
          fleet_id: fleet-a
          environment: production
          labels:
            region: ap-southeast-1
          metadata:
            owner: platform

        postgres:
      YAML
    end
  end
end
