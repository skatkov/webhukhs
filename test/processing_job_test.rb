# frozen_string_literal: true

require "test_helper"

class SkipDuringProcessingHandler < Webhukhs::BaseHandler
  def process(webhook)
    webhook.skipped!
  end
end

class LoggingHandler < Webhukhs::BaseHandler
  class_attribute :processed_webhook_ids, default: []

  def self.reset!
    self.processed_webhook_ids = []
  end

  def to_s = self.class.name

  def valid?(_request) = true

  def process(webhook)
    self.class.processed_webhook_ids += [webhook.id]
  end
end

class InvalidLoggingHandler < LoggingHandler
  def valid?(_request) = false
end

class ProcessingJobTest < ActiveJob::TestCase
  cover "Webhukhs::ProcessingJob*"

  teardown do
    Webhukhs::ReceivedWebhook.delete_all
    LoggingHandler.reset!
    InvalidLoggingHandler.reset!
  end

  test "discards job and reports invalid webhook arguments" do
    events = captured_webhukhs_events do
      [nil, "not a webhook"].each do |argument|
        Webhukhs::ProcessingJob.perform_now(argument)
      end
    end

    assert_equal 2, events.size
    events.each do |event|
      assert_equal :process, event.fetch(:operation)
      assert_equal :discarded, event.fetch(:outcome)
      assert_equal :error, event.fetch(:severity)
      assert_instance_of Webhukhs::ProcessingJob::InvalidWebhookArgument, event.fetch(:error)
    end
  end

  test "raises specific invalid webhook argument messages" do
    {
      nil => "ProcessingJob received nil webhook argument",
      "not a webhook" => "ProcessingJob expected Webhukhs::ReceivedWebhook, got String"
    }.each do |argument, message|
      error = assert_raises(Webhukhs::ProcessingJob::InvalidWebhookArgument) do
        Webhukhs::ProcessingJob.new.perform(argument)
      end

      assert_equal message, error.message
    end
  end

  test "processes webhooks under a lock" do
    webhook = Webhukhs::ReceivedWebhook.create!(
      handler_event_id: "lock-test",
      handler_module_name: "WebhookTestHandler",
      status: "received",
      body: {isValid: false}.to_json,
      request_headers: {
        "CONTENT_TYPE" => "application/json",
        "action_dispatch.request.path_parameters" => {}
      }
    )
    with_lock_called = false

    webhook.define_singleton_method(:with_lock) do |&block|
      with_lock_called = true
      block.call
    end

    Webhukhs::ProcessingJob.new.perform(webhook)

    assert_true with_lock_called
    assert_predicate webhook.reload, :failed_validation?
  end

  test "emits event when processing is skipped because the webhook is not received" do
    webhook = Webhukhs::ReceivedWebhook.create!(
      handler_event_id: "skip-log-test",
      handler_module_name: "LoggingHandler",
      status: "processing",
      body: {}.to_json,
      request_headers: {}
    )
    job = Webhukhs::ProcessingJob.new

    events = captured_webhukhs_events do
      job.perform(webhook)
    end

    assert_equal 1, events.size
    event = events.fetch(0)
    assert_equal :process, event.fetch(:operation)
    assert_equal :skipped, event.fetch(:outcome)
    assert_equal :info, event.fetch(:severity)
    assert_equal webhook.id, event.fetch(:webhook_id)
    assert_equal "LoggingHandler", event.fetch(:handler_class)
  end

  test "emits events when processing starts and completes" do
    webhook = Webhukhs::ReceivedWebhook.create!(
      handler_event_id: "success-log-test",
      handler_module_name: "LoggingHandler",
      status: "received",
      body: {}.to_json,
      request_headers: {
        "CONTENT_TYPE" => "application/json",
        "action_dispatch.request.path_parameters" => {}
      }
    )
    job = Webhukhs::ProcessingJob.new

    events = captured_webhukhs_events do
      job.perform(webhook)
    end

    assert_equal [:started, :completed], events.map { |event| event.fetch(:outcome) }
    events.each do |event|
      assert_equal :process, event.fetch(:operation)
      assert_equal :info, event.fetch(:severity)
      assert_equal webhook.id, event.fetch(:webhook_id)
      assert_equal "LoggingHandler", event.fetch(:handler_class)
    end

    assert_predicate webhook.reload, :processed?
    assert_equal [webhook.id], LoggingHandler.processed_webhook_ids
  end

  test "emits event when validation fails" do
    webhook = Webhukhs::ReceivedWebhook.create!(
      handler_event_id: "failed-validation-log-test",
      handler_module_name: "InvalidLoggingHandler",
      status: "received",
      body: {}.to_json,
      request_headers: {
        "CONTENT_TYPE" => "application/json",
        "action_dispatch.request.path_parameters" => {}
      }
    )
    job = Webhukhs::ProcessingJob.new

    events = captured_webhukhs_events do
      job.perform(webhook)
    end

    assert_equal 1, events.size
    event = events.fetch(0)
    assert_equal :process, event.fetch(:operation)
    assert_equal :validation_failed, event.fetch(:outcome)
    assert_equal :info, event.fetch(:severity)
    assert_equal webhook.id, event.fetch(:webhook_id)
    assert_equal "InvalidLoggingHandler", event.fetch(:handler_class)

    assert_predicate webhook.reload, :failed_validation?
  end

  test "does not overwrite webhook state changed by the handler" do
    webhook = Webhukhs::ReceivedWebhook.create!(
      handler_event_id: "skip-test",
      handler_module_name: "SkipDuringProcessingHandler",
      status: "received",
      body: {}.to_json,
      request_headers: {
        "CONTENT_TYPE" => "application/json",
        "action_dispatch.request.path_parameters" => {}
      }
    )

    Webhukhs::ProcessingJob.new.perform(webhook)

    assert_predicate webhook.reload, :skipped?
  end

  test "discards job and reports error when webhook record has been deleted (DeserializationError)" do
    webhook = Webhukhs::ReceivedWebhook.create!(
      handler_event_id: "deserialization-test",
      handler_module_name: "WebhookTestHandler",
      status: "received",
      body: {isValid: true}.to_json
    )

    Webhukhs::ProcessingJob.perform_later(webhook)
    webhook.destroy!

    events = captured_webhukhs_events do
      perform_enqueued_jobs
    end

    assert_equal 1, events.size
    event = events.fetch(0)
    assert_equal :process, event.fetch(:operation)
    assert_equal :discarded, event.fetch(:outcome)
    assert_equal :error, event.fetch(:severity)
    assert_instance_of ActiveJob::DeserializationError, event.fetch(:error)
  end
end
