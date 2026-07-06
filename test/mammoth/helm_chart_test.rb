# frozen_string_literal: true

require "open3"
require "test_helper"
require "tempfile"

module Mammoth
  class HelmChartTest < Minitest::Test
    def test_chart_renders_runtime_and_webhook_auth_config
      stdout, stderr, status = Open3.capture3(*helm_template_command)

      assert status.success?, stderr
      expected_rendered_config.each { |content| assert_includes stdout, content }
    end

    def test_chart_renders_fanout_destinations_with_secret_backed_env
      Tempfile.create(["mammoth-values", ".yml"]) do |file|
        file.write(fanout_values)
        file.flush

        stdout, stderr, status = Open3.capture3("helm", "template", "mammoth", "charts/mammoth", "--values", file.path)

        assert status.success?, stderr
        fanout_expected_rendered_config.each { |content| assert_includes stdout, content }
      end
    end

    private

    def helm_template_command
      [
        "helm",
        "template",
        "mammoth",
        "charts/mammoth",
        "--set",
        "webhook.header_env.Authorization=MAMMOTH_WEBHOOK_AUTHORIZATION",
        "--set",
        "webhook.signing.algorithm=hmac_sha256",
        "--set",
        "webhook.signing.secret_env=MAMMOTH_WEBHOOK_SIGNING_SECRET",
        "--set",
        "webhook.existingSecret.name=webhook-secrets",
        "--set",
        "webhook.existingSecret.keys.MAMMOTH_WEBHOOK_AUTHORIZATION=authorization",
        "--set",
        "webhook.existingSecret.keys.MAMMOTH_WEBHOOK_SIGNING_SECRET=signing-secret"
      ]
    end

    def expected_rendered_config
      [
        "image: \"ghcr.io/kanutocd/mammoth:0.7.1\"",
        "unit: \"transaction\"",
        "adapter: \"concurrent\"",
        "Authorization: MAMMOTH_WEBHOOK_AUTHORIZATION",
        "secret_env: MAMMOTH_WEBHOOK_SIGNING_SECRET",
        "name: MAMMOTH_WEBHOOK_AUTHORIZATION",
        "key: authorization",
        "name: MAMMOTH_WEBHOOK_SIGNING_SECRET",
        "key: signing-secret"
      ]
    end

    def fanout_values
      <<~YAML
        destinations:
          - name: primary_webhook
            type: webhook
            url: https://example.com/webhooks/postgres
            timeout_seconds: 5
            header_env:
              Authorization: MAMMOTH_PRIMARY_WEBHOOK_AUTHORIZATION
            signing:
              algorithm: hmac_sha256
              secret_env: MAMMOTH_PRIMARY_WEBHOOK_SIGNING_SECRET
            existingSecret:
              name: primary-webhook-secrets
              keys:
                MAMMOTH_PRIMARY_WEBHOOK_AUTHORIZATION: authorization
                MAMMOTH_PRIMARY_WEBHOOK_SIGNING_SECRET: signing-secret
          - name: audit_webhook
            type: webhook
            enabled: false
            url: https://audit.example.com/cdc
            timeout_seconds: 5
            route:
              schemas:
                - public
              tables:
                - orders
              operations:
                - insert
                - update
            retry:
              max_attempts: 3
              schedule_seconds:
                - 1
                - 10
      YAML
    end

    def fanout_expected_rendered_config
      [
        "destinations:",
        "name: \"primary_webhook\"",
        "name: \"audit_webhook\"",
        "enabled: false",
        "schemas:",
        "- public",
        "max_attempts: 3",
        "Authorization: MAMMOTH_PRIMARY_WEBHOOK_AUTHORIZATION",
        "secret_env: MAMMOTH_PRIMARY_WEBHOOK_SIGNING_SECRET",
        "name: MAMMOTH_PRIMARY_WEBHOOK_AUTHORIZATION",
        "key: authorization",
        "name: MAMMOTH_PRIMARY_WEBHOOK_SIGNING_SECRET",
        "key: signing-secret"
      ]
    end
  end
end
