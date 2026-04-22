# frozen_string_literal: true

require "test_helper"
require_relative "test_app"

class SkipDuringProcessingHandler < Webhukhs::BaseHandler
  def process(webhook)
    webhook.skipped!
  end
end

class ProcessingJobTest < ActiveJob::TestCase
  cover "Webhukhs::ProcessingJob*"

  teardown { Webhukhs::ReceivedWebhook.delete_all }

  test "discards job and reports error when webhook argument is nil" do
    assert_error_reported(Webhukhs::ProcessingJob::InvalidWebhookArgument) do
      Webhukhs::ProcessingJob.perform_now(nil)
    end

    assert_no_enqueued_jobs only: Webhukhs::ProcessingJob
  end

  test "raises a specific error message when webhook argument is nil" do
    error = assert_raises(Webhukhs::ProcessingJob::InvalidWebhookArgument) do
      Webhukhs::ProcessingJob.new.perform(nil)
    end

    assert_equal "ProcessingJob received nil webhook argument", error.message
  end

  test "discards job and reports error when webhook argument is not a ReceivedWebhook" do
    assert_error_reported(Webhukhs::ProcessingJob::InvalidWebhookArgument) do
      Webhukhs::ProcessingJob.perform_now("not a webhook")
    end

    assert_no_enqueued_jobs only: Webhukhs::ProcessingJob
  end

  test "raises a specific error message when webhook argument is not a ReceivedWebhook" do
    error = assert_raises(Webhukhs::ProcessingJob::InvalidWebhookArgument) do
      Webhukhs::ProcessingJob.new.perform("not a webhook")
    end

    assert_equal "ProcessingJob expected Webhukhs::ReceivedWebhook, got String", error.message
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

    assert_equal true, with_lock_called
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

    assert_error_reported(ActiveJob::DeserializationError) do
      perform_enqueued_jobs
    end

    assert_no_enqueued_jobs only: Webhukhs::ProcessingJob
  end
end
