# frozen_string_literal: true

require_relative "../../app/webhooks/webhook_test_handler"

Webhukhs.configure do |config|
  config.active_handlers = {
    "test-handler" => "WebhookTestHandler"
  }
end
