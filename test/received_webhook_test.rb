# frozen_string_literal: true

require "test_helper"

class StringIdReceivedWebhook < Webhukhs::ReceivedWebhook
  self.table_name = "string_id_received_webhooks"
end

unless ActiveRecord::Base.connection.data_source_exists?("string_id_received_webhooks")
  original_migration_verbose = ActiveRecord::Migration.verbose
  ActiveRecord::Migration.verbose = false

  begin
    ActiveRecord::Schema.define do
      create_table "string_id_received_webhooks", id: :string, force: true do |t|
        t.string "handler_event_id", null: false
        t.string "handler_module_name", null: false
        t.string "status", default: "received", null: false
        t.binary "body", null: false
        t.json "request_headers", null: true
        t.datetime "created_at", null: false
        t.datetime "updated_at", null: false
      end
    end
  ensure
    ActiveRecord::Migration.verbose = original_migration_verbose
  end
end

class ReceivedWebhookTest < ActiveSupport::TestCase
  cover "Webhukhs::ReceivedWebhook*"

  teardown do
    Webhukhs::ReceivedWebhook.delete_all
    StringIdReceivedWebhook.delete_all if ActiveRecord::Base.connection.data_source_exists?("string_id_received_webhooks")
  end

  test "request stores uppercase string headers and rewinds the body io" do
    body_io = StringIO.new('{"ok":true}')
    request = ActionDispatch::Request.new(
      "CONTENT_TYPE" => "application/json",
      "HTTP_X_SIGNATURE" => "sig",
      "lowercase" => "skip",
      "Mixed-Case" => "skip",
      "HTTP_X_NUMBER" => 123,
      123 => "skip",
      "RAW_POST_DATA" => "legacy",
      "rack.input" => body_io,
      "action_dispatch.request.path_parameters" => {"user_id" => "123"}
    )
    webhook = Webhukhs::ReceivedWebhook.new

    webhook.request = request

    assert_equal 0, body_io.pos
    assert_equal body_io.string.b, webhook.body
    assert_equal Encoding::ASCII_8BIT, webhook.body.encoding
    assert_equal(
      {
        "CONTENT_TYPE" => "application/json",
        "HTTP_X_SIGNATURE" => "sig",
        "action_dispatch.request.path_parameters" => {"user_id" => "123"}
      },
      webhook.request_headers
    )
  end

  test "request writer coerces the stored body to binary before type casting" do
    body_io = StringIO.new("payload")
    request = ActionDispatch::Request.new(
      "CONTENT_TYPE" => "application/json",
      "rack.input" => body_io,
      "action_dispatch.request.path_parameters" => {}
    )
    webhook = Webhukhs::ReceivedWebhook.new
    captured_body = nil

    with_overridden_singleton_method(webhook, :write_attribute, ->(name, value) {
      captured_body = value if name == "body"
    }) do
      webhook.request = request

      assert_equal "payload".b, captured_body
      assert_equal Encoding::ASCII_8BIT, captured_body.encoding
    end
  end

  test "request rejects oversized bodies and rewinds the body io" do
    original_limit = Webhukhs.configuration.request_body_size_limit
    Webhukhs.configuration.request_body_size_limit = 3

    body_io = StringIO.new("four")
    request = ActionDispatch::Request.new(
      "CONTENT_TYPE" => "application/json",
      "rack.input" => body_io,
      "action_dispatch.request.path_parameters" => {}
    )
    webhook = Webhukhs::ReceivedWebhook.new

    error = assert_raises(RuntimeError) { webhook.request = request }

    assert_equal "Cannot accept the webhook as the request body is larger than 3 bytes", error.message
    assert_equal 0, body_io.pos
  ensure
    Webhukhs.configuration.request_body_size_limit = original_limit
  end

  test "request reconstructs the body without mutating stored headers" do
    request_headers = {
      "CONTENT_TYPE" => "application/json",
      "action_dispatch.request.path_parameters" => {"user_id" => "123"}
    }
    webhook = Webhukhs::ReceivedWebhook.new(
      handler_event_id: "request-read",
      handler_module_name: "WebhookTestHandler",
      status: "received",
      body: "payload",
      request_headers: request_headers.deep_dup
    )

    request = webhook.request
    request_body = request.body.read

    assert_equal "payload".b, request_body.b
    assert_equal Encoding::ASCII_8BIT, request_body.encoding
    assert_equal request_headers, webhook.request_headers
  end

  test "request reader coerces the reconstructed body to binary" do
    webhook = Webhukhs::ReceivedWebhook.new

    request_headers = {
      "CONTENT_TYPE" => "application/json",
      "action_dispatch.request.path_parameters" => {}
    }

    with_overridden_singleton_methods(webhook, {
      body: -> { "payload" },
      request_headers: -> {
        request_headers
      }
    }) do
      request_body = webhook.request.body.read

      assert_equal "payload".b, request_body.b
      assert_equal Encoding::ASCII_8BIT, request_body.encoding
    end
  end

  test "assigns uuid ids for string primary keys" do
    with_overridden_singleton_methods(SecureRandom, {
      respond_to?: ->(method_name, include_all = false) {
        method_name == :uuid_v7 || super(method_name, include_all)
      },
      uuid_v7: -> {
        "00000000-0000-7000-8000-000000000001"
      },
      uuid: -> {
        "00000000-0000-4000-8000-000000000002"
      }
    }) do
      webhook = StringIdReceivedWebhook.create!(
        handler_event_id: "generated-id-event",
        handler_module_name: "WebhookTestHandler",
        status: "received",
        body: {}.to_json,
        request_headers: {}
      )

      assert_equal "00000000-0000-7000-8000-000000000001", webhook.id
    end
  end

  test "falls back to uuid when uuid_v7 is unavailable" do
    with_overridden_singleton_methods(SecureRandom, {
      respond_to?: ->(method_name, include_all = false) {
        method_name == :uuid_v7 ? false : super(method_name, include_all)
      },
      uuid_v7: -> {
        raise "uuid_v7 should not be called when unavailable"
      },
      uuid: -> {
        "00000000-0000-4000-8000-000000000002"
      }
    }) do
      webhook = StringIdReceivedWebhook.create!(
        handler_event_id: "fallback-id-event",
        handler_module_name: "WebhookTestHandler",
        status: "received",
        body: {}.to_json,
        request_headers: {}
      )

      assert_equal "00000000-0000-4000-8000-000000000002", webhook.id
    end
  end

  test "does not call uuid generation for integer primary keys" do
    with_overridden_singleton_methods(SecureRandom, {
      uuid_v7: -> {
        raise "uuid_v7 should not be called for integer primary keys"
      },
      uuid: -> {
        raise "uuid should not be called for integer primary keys"
      }
    }) do
      webhook = Webhukhs::ReceivedWebhook.create!(
        handler_event_id: "integer-id-event",
        handler_module_name: "WebhookTestHandler",
        status: "received",
        body: {}.to_json,
        request_headers: {}
      )

      assert_kind_of Integer, webhook.id
    end
  end

  test "does not overwrite explicitly assigned string ids" do
    webhook = StringIdReceivedWebhook.create!(
      id: "manual-id",
      handler_event_id: "manual-id-event",
      handler_module_name: "WebhookTestHandler",
      status: "received",
      body: {}.to_json,
      request_headers: {}
    )

    assert_equal "manual-id", webhook.id
  end

  test "assigns a uuid when a string id is blank" do
    webhook = StringIdReceivedWebhook.create!(
      id: "",
      handler_event_id: "blank-id-event",
      handler_module_name: "WebhookTestHandler",
      status: "received",
      body: {}.to_json,
      request_headers: {}
    )

    assert_match(/\A[0-9a-f\-]{36}\z/, webhook.id)
  end

end
