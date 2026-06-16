# frozen_string_literal: true

require "test_helper"

module Mammoth
  class StatusTest < Minitest::Test
    def test_prints_status_without_sqlite_store
      config = Configuration.load(fixture_config_path)

      stdout, stderr = capture_io { Status.call(config) }

      assert_empty stderr
      assert_match(/Mammoth: local_mammoth/, stdout)
      assert_match(/Runtime: not started/, stdout)
      assert_match(/Replication publications: mammoth_publication/, stdout)
      assert_match(/Webhook: primary_webhook/, stdout)
      refute_match(/Tables:/, stdout)
    end
  end
end
