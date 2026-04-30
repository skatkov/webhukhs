# frozen_string_literal: true

require "test_helper"

class EnqueueProbeJob
  class << self
    attr_accessor :received_webhook
  end

  def self.perform_later(webhook)
    self.received_webhook = webhook
  end
end

class HandleProbeHandler < Webhukhs::BaseHandler
  attr_reader :enqueued_webhook

  def to_s = "custom handler string"

  def enqueue(webhook)
    @enqueued_webhook = webhook
  end
end

class CustomStringExtractIdHandler < ExtractIdHandler
  def to_s = "custom extract id handler string"
end

class BaseHandlerTest < ActiveSupport::TestCase
  cover "Webhukhs::BaseHandler*"

  teardown { Webhukhs::ReceivedWebhook.delete_all }

  test "process is a no-op by default" do
    assert_nil Webhukhs::BaseHandler.new.process(nil)
  end

  test "defaults to active, valid and exposing errors" do
    handler = Webhukhs::BaseHandler.new

    assert_true handler.active?
    assert_true handler.valid?(nil)
    assert_true handler.expose_errors_to_sender?
  end

  test "generates unique UUID event ids by default" do
    handler = Webhukhs::BaseHandler.new

    first_id = handler.extract_event_id_from_request(nil)
    second_id = handler.extract_event_id_from_request(nil)

    assert_match(/\A[0-9a-f-]{36}\z/, first_id)
    assert_match(/\A[0-9a-f-]{36}\z/, second_id)
    refute_equal first_id, second_id
  end

  test "handle passes the handler module name into received webhooks" do
    captured_attributes = nil
    request = ActionDispatch::Request.new(
      "rack.input" => StringIO.new("{}"),
      "REQUEST_METHOD" => "POST",
      "CONTENT_TYPE" => "application/json",
      "action_dispatch.request.path_parameters" => {}
    )
    webhook = Object.new
    handler = HandleProbeHandler.new

    def webhook.save!
    end

    with_overridden_singleton_method(Webhukhs::ReceivedWebhook, :new, ->(**attributes) {
      captured_attributes = attributes
      webhook
    }) do
      handler.handle(request)

      assert_same webhook, handler.enqueued_webhook
      assert_equal "HandleProbeHandler", captured_attributes.fetch(:handler_module_name)
    end
  end

  test "handle emits duplicate delivery events" do
    handler = CustomStringExtractIdHandler.new
    request_headers = {
      "CONTENT_TYPE" => "application/json",
      "action_dispatch.request.path_parameters" => {}
    }
    payload = {event_id: "duplicate-event"}.to_json

    first_request = ActionDispatch::Request.new(request_headers.merge("rack.input" => StringIO.new(payload)))
    second_request = ActionDispatch::Request.new(request_headers.merge("rack.input" => StringIO.new(payload)))

    handler.handle(first_request)

    events = captured_webhukhs_events do
      handler.handle(second_request)
    end

    assert_equal 1, events.size
    event = events.fetch(0)
    assert_equal :receive, event.fetch(:operation)
    assert_equal :duplicate, event.fetch(:outcome)
    assert_equal :warn, event.fetch(:severity)
    assert_equal "CustomStringExtractIdHandler", event.fetch(:handler_class)
    assert_equal "duplicate-event", event.fetch(:handler_event_id)
  end

  test "enqueue uses configured processing job classes directly" do
    original_job_class = Webhukhs.configuration.processing_job_class
    webhook = Object.new

    Webhukhs.configuration.processing_job_class = EnqueueProbeJob
    EnqueueProbeJob.received_webhook = nil

    Webhukhs::BaseHandler.new.enqueue(webhook)

    assert_same webhook, EnqueueProbeJob.received_webhook
  ensure
    Webhukhs.configuration.processing_job_class = original_job_class
    EnqueueProbeJob.received_webhook = nil
  end

  test "enqueue constantizes configured processing job class names" do
    original_job_class = Webhukhs.configuration.processing_job_class
    webhook = Object.new

    Webhukhs.configuration.processing_job_class = "EnqueueProbeJob"
    EnqueueProbeJob.received_webhook = nil

    Webhukhs::BaseHandler.new.enqueue(webhook)

    assert_same webhook, EnqueueProbeJob.received_webhook
  ensure
    Webhukhs.configuration.processing_job_class = original_job_class
    EnqueueProbeJob.received_webhook = nil
  end
end
