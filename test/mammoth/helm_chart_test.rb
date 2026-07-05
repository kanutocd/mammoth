# frozen_string_literal: true

require "open3"
require "test_helper"

module Mammoth
  class HelmChartTest < Minitest::Test
    def test_chart_renders_0_2_runtime_and_webhook_auth_config
      stdout, stderr, status = Open3.capture3(*helm_template_command)

      assert status.success?, stderr
      expected_rendered_config.each { |content| assert_includes stdout, content }
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
        "image: \"ghcr.io/kanutocd/mammoth:0.3.0\"",
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
  end
end
