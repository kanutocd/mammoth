# frozen_string_literal: true

require "fileutils"
require "simplecov"

SimpleCov.external_at_exit = true
SimpleCov.start do
  enable_coverage :branch
  add_filter "/test/"
  minimum_coverage line: 99, branch: 99 unless ENV["MAMMOTH_E2E"] == "1"
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

FAKE_RUNTIME_DIR = File.expand_path("tmp/fake_runtimes", __dir__)
FileUtils.mkdir_p(File.join(FAKE_RUNTIME_DIR, "cdc"))
File.write(File.join(FAKE_RUNTIME_DIR, "cdc", "concurrent.rb"), <<~FAKE_CONCURRENT)
  module CDC
    module Concurrent
      class ProcessorPool
        def self.last_options = @last_options

        def initialize(processor:, concurrency:, timeout:, preserve_order:)
          @processor = processor
          @shutdown = false
          self.class.instance_variable_set(
            :@last_options,
            { processor: processor, concurrency: concurrency, timeout: timeout, preserve_order: preserve_order }
          )
        end

        def process_many(items)
          items.map { |item| @processor.process(item) }.freeze
        end

        def shutdown
          @shutdown = true
        end
      end
    end
  end
FAKE_CONCURRENT
$LOAD_PATH.unshift FAKE_RUNTIME_DIR

require "mammoth"

require "minitest/autorun"
require "stringio"
require "tempfile"
require "tmpdir"

module MammothTestHelpers
  def fixture_config_path
    File.expand_path("../config/mammoth.example.yml", __dir__)
  end

  def with_temp_dir(&block)
    Dir.mktmpdir("mammoth-test-", &block)
  end

  def write_file(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  def minimal_config(sqlite_path: "data/mammoth.db", webhook_url: "https://example.com/webhooks/postgres")
    <<~YAML
      mammoth:
        name: local_mammoth

      postgres:
        host: localhost
        port: 5432
        database: app_development
        username: mammoth
        password_env: MAMMOTH_POSTGRES_PASSWORD

      replication:
        slot: mammoth_prod
        publications:
          - mammoth_publication
        auto_create_slot: false
        temporary_slot: false
        feedback_interval: 10.0

      webhook:
        name: primary_webhook
        url: #{webhook_url}
        timeout_seconds: 5

      retry:
        max_attempts: 5
        schedule_seconds:
          - 1
          - 5

      sqlite:
        path: #{sqlite_path}

      logging:
        level: info
    YAML
  end
end

module Minitest
  class Test
    include MammothTestHelpers
  end
end
