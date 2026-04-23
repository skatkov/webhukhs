# frozen_string_literal: true

require "test_helper"

class FailingLookupReceiveWebhooksController < Webhukhs::ReceiveWebhooksController
  def initialize(error)
    super()
    @error = error
  end

  def service_id = "broken"

  def lookup_handler(_service_id)
    raise @error
  end
end

class TestWebhukhs < ActionDispatch::IntegrationTest
  cover "Webhukhs*"
  cover "Webhukhs::BaseHandler*"
  cover "Webhukhs::Configuration*"
  cover "Webhukhs::ProcessingJob*"
  cover "Webhukhs::ReceiveWebhooksController*"
  cover "Webhukhs::ReceivedWebhook*"

  teardown { Webhukhs::ReceivedWebhook.delete_all }

  def test_that_it_has_a_version_number
    refute_nil ::Webhukhs::VERSION
  end

  def webhook_body
    <<~JSON
      {
        "provider_id": "musterbank-flyio",
        "starts_at": "<%= Time.now.utc %>",
        "external_source": "The Forge Of Downtime",
        "external_ticket_title": "DOWN-123",
        "internal_description_markdown": "A test has failed"
      }
    JSON
  end

  self.app = WebhukhsTestApp

  def self.xtest(msg)
    test(msg) { skip }
  end

  test "returns a memoized configuration object and yields it to configure" do
    original_configuration = Webhukhs.instance_variable_get(:@configuration)
    Webhukhs.remove_instance_variable(:@configuration) if Webhukhs.instance_variable_defined?(:@configuration)

    configuration = Webhukhs.configuration

    assert_instance_of Webhukhs::Configuration, configuration
    assert_same configuration, Webhukhs.configuration

    yielded = nil
    Webhukhs.configure { |config| yielded = config }

    assert_same configuration, yielded
  ensure
    Webhukhs.instance_variable_set(:@configuration, original_configuration)
  end

  test "applies the configured error context before handling requests" do
    original_error_context = Webhukhs.configuration.error_context

    Webhukhs.configuration.error_context = {component: "webhooks"}

    report = assert_error_reported(RuntimeError) do
      post "/webhukhs/failing-with-concealed-errors", params: webhook_body, headers: {"CONTENT_TYPE" => "application/json"}

      assert_response 200
    end

    assert_equal "webhooks", report.context[:component]
  ensure
    Webhukhs.configuration.error_context = original_error_context
  end

  test "ensure webhook is processed only once during creation" do
    tf = Tempfile.new
    body = {isValid: true, outputToFilename: tf.path}
    body_json = body.to_json

    assert_enqueued_jobs 1, only: Webhukhs::ProcessingJob do
      post "/webhukhs/test", params: body_json, headers: {"CONTENT_TYPE" => "application/json"}
      assert_response 200
      assert_equal({"ok" => true, "error" => nil}, response.parsed_body)
    end
  end

  test "accepts a webhook, stores and processes it" do
    tf = Tempfile.new
    body = {isValid: true, outputToFilename: tf.path}
    body_json = body.to_json

    post "/webhukhs/test", params: body_json, headers: {"CONTENT_TYPE" => "application/json"}
    assert_response 200

    webhook = Webhukhs::ReceivedWebhook.last!

    assert_predicate webhook, :received?
    assert_equal "WebhookTestHandler", webhook.handler_module_name
    assert_equal webhook.status, "received"
    assert_equal webhook.body, body_json

    perform_enqueued_jobs
    assert_predicate webhook.reload, :processed?
    tf.rewind
    assert_equal tf.read, body_json
  end

  test "accepts a webhook but does not process it if it is invalid" do
    tf = Tempfile.new
    body = {isValid: false, outputToFilename: tf.path}
    body_json = body.to_json

    post "/webhukhs/test", params: body_json, headers: {"CONTENT_TYPE" => "application/json"}
    assert_response 200

    webhook = Webhukhs::ReceivedWebhook.last!

    assert_predicate webhook, :received?
    assert_equal "WebhookTestHandler", webhook.handler_module_name
    assert_equal webhook.status, "received"
    assert_equal webhook.body, body_json

    perform_enqueued_jobs
    assert_predicate webhook.reload, :failed_validation?

    tf.rewind
    assert_predicate tf.read, :empty?
  end

  test "marks a webhook as errored if it raises during processing" do
    tf = Tempfile.new
    body = {isValid: true, raiseDuringProcessing: true, outputToFilename: tf.path}
    body_json = body.to_json

    post "/webhukhs/test", params: body_json, headers: {"CONTENT_TYPE" => "application/json"}
    assert_response 200

    webhook = Webhukhs::ReceivedWebhook.last!

    assert_predicate webhook, :received?
    assert_equal "WebhookTestHandler", webhook.handler_module_name
    assert_equal webhook.status, "received"
    assert_equal webhook.body, body_json

    assert_raises(StandardError) { perform_enqueued_jobs }
    assert_predicate webhook.reload, :error?

    tf.rewind
    assert_predicate tf.read, :empty?
  end

  test "does not accept a test payload that is larger than the configured maximum size" do
    oversize = Webhukhs.configuration.request_body_size_limit + 1
    utf8_junk = Base64.strict_encode64(Random.bytes(oversize))
    body = {isValid: true, filler: utf8_junk, raiseDuringProcessing: false, outputToFilename: "/tmp/nothing"}
    body_json = body.to_json

    post "/webhukhs/test", params: body_json, headers: {"CONTENT_TYPE" => "application/json"}
    assert_raises(ActiveRecord::RecordNotFound) { Webhukhs::ReceivedWebhook.last! }
  end

  test "does not try to process a webhook if it is not in `received' state" do
    tf = Tempfile.new
    body = {isValid: true, raiseDuringProcessing: true, outputToFilename: tf.path}
    body_json = body.to_json

    post "/webhukhs/test", params: body_json, headers: {"CONTENT_TYPE" => "application/json"}
    assert_response 200

    webhook = Webhukhs::ReceivedWebhook.last!
    webhook.processing!

    perform_enqueued_jobs
    assert_predicate webhook.reload, :processing?

    tf.rewind
    assert_predicate tf.read, :empty?
  end

  test "raises an error if the service_id is not known" do
    report = assert_error_reported(Webhukhs::ReceiveWebhooksController::UnknownHandler) do
      post "/webhukhs/missing_service", params: webhook_body, headers: {"CONTENT_TYPE" => "application/json"}

      assert_response 404
      assert_equal "No handler found for \"missing_service\"", response.parsed_body["error"]
    end

    assert_predicate report, :handled?
    assert_equal :error, report.severity
  end

  test "returns a 503 when a handler is inactive" do
    report = assert_error_reported(Webhukhs::ReceiveWebhooksController::HandlerInactive) do
      post "/webhukhs/inactive", params: webhook_body, headers: {"CONTENT_TYPE" => "application/json"}

      assert_response 503
      assert_equal 'Webhook handler "inactive" is inactive', response.parsed_body["error"]
    end

    assert_predicate report, :handled?
    assert_equal :error, report.severity
  end

  test "returns a 200 status and error message if the handler does not expose errors" do
    report = assert_error_reported(RuntimeError) do
      post "/webhukhs/failing-with-concealed-errors", params: webhook_body, headers: {"CONTENT_TYPE" => "application/json"}

      assert_response 200
      assert_equal false, response.parsed_body["ok"]
      assert_equal "Internal error (oops)", response.parsed_body["error"]
    end

    assert_predicate report, :handled?
    assert_equal :error, report.severity
  end

  test "returns a 500 status and error message if the handler does not expose errors" do
    post "/webhukhs/failing-with-exposed-errors", params: webhook_body, headers: {"CONTENT_TYPE" => "application/json"}

    assert_response 500
    # The response generation in this case is done by Rails, through the
    # common Rails error page
  end

  test "re-raises lookup errors before a handler has been assigned" do
    original_active_handlers = Webhukhs.configuration.active_handlers
    Webhukhs.configuration.active_handlers = original_active_handlers.merge(broken: "MissingHandler")

    post "/webhukhs/broken", params: webhook_body, headers: {"CONTENT_TYPE" => "application/json"}

    assert_response 500
    assert_includes response.body, "NameError"
    assert_includes response.body, "MissingHandler"
  ensure
    Webhukhs.configuration.active_handlers = original_active_handlers
  end

  test "re-raises the original error when lookup fails before assigning a handler" do
    original_error = NameError.new("uninitialized constant MissingHandler")
    controller = FailingLookupReceiveWebhooksController.new(original_error)

    raised_error = assert_raises(NameError) { controller.create }

    assert_same original_error, raised_error
  end

  test "accepts handlers configured as class constants" do
    original_active_handlers = Webhukhs.configuration.active_handlers
    Webhukhs.configuration.active_handlers = original_active_handlers.merge(class_handler: WebhookTestHandler)

    post "/webhukhs/class_handler", params: {isValid: false, outputToFilename: "/tmp/unused"}.to_json, headers: {"CONTENT_TYPE" => "application/json"}

    assert_response 200
    assert_equal({"ok" => true, "error" => nil}, response.parsed_body)
  ensure
    Webhukhs.configuration.active_handlers = original_active_handlers
  end

  test "deduplicates received webhooks based on the event ID" do
    body = {event_id: SecureRandom.uuid, body: "test"}.to_json

    assert_changes_by -> { Webhukhs::ReceivedWebhook.count }, exactly: 1 do
      3.times do
        post "/webhukhs/extract_id", params: body, headers: {"CONTENT_TYPE" => "application/json"}
        assert_response 200
      end
    end
  end

  test "preserves the route params and the request params in the serialised request stored with the webhook" do
    body = {user_name: "John", number_of_dependents: 14}.to_json

    Webhukhs::ReceivedWebhook.delete_all
    post "/per-user-webhukhs/123/private", params: body, headers: {"CONTENT_TYPE" => "application/json"}
    assert_response 200

    received_webhook = Webhukhs::ReceivedWebhook.first!
    assert_predicate received_webhook, :received?
    assert_equal body, received_webhook.request.body.read
    assert_equal "John", received_webhook.request.params["user_name"]
    assert_equal 14, received_webhook.request.params["number_of_dependents"]
    assert_equal "123", received_webhook.request.params["user_id"]
  end

  test "erroneous webhook could be processed again" do
    webhook = Webhukhs::ReceivedWebhook.create(
      handler_event_id: "test",
      handler_module_name: "WebhookTestHandler",
      status: "error",
      body: {isValid: true}.to_json
    )

    assert_enqueued_jobs 1, only: Webhukhs::ProcessingJob do
      webhook.received!

      assert_equal "received", webhook.status
    end
  end

  test "ensure_id does not override id for integer primary key columns" do
    webhook = Webhukhs::ReceivedWebhook.create!(
      handler_event_id: SecureRandom.uuid,
      handler_module_name: "WebhookTestHandler",
      status: "received",
      body: {isValid: true}.to_json
    )

    assert_kind_of Integer, webhook.id
    assert webhook.id > 0
  end
end
