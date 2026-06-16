# frozen_string_literal: true

require "simplecov"

SimpleCov.external_at_exit = true
SimpleCov.start do
  enable_coverage :branch
  add_filter "/test/"
  minimum_coverage line: 95, branch: 95 unless ENV["MAMMOTH_E2E"] == "1"
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "mammoth"

require "fileutils"
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
        password_env: HARBINGER_POSTGRES_PASSWORD

      replication:
        slot: mammoth_prod
        publication: mammoth_publication

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
