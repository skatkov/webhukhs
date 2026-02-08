# frozen_string_literal: true

require "test_helper"
require_relative "test_app"

class ProcessingJobTest < ActiveJob::TestCase
  teardown { Webhukhs::ReceivedWebhook.delete_all }

  test "discards job and reports error when webhook argument is nil" do
    assert_error_reported(Webhukhs::ProcessingJob::InvalidWebhookArgument) do
      Webhukhs::ProcessingJob.perform_now(nil)
    end

    assert_no_enqueued_jobs only: Webhukhs::ProcessingJob
  end

  test "discards job and reports error when webhook argument is not a ReceivedWebhook" do
    assert_error_reported(Webhukhs::ProcessingJob::InvalidWebhookArgument) do
      Webhukhs::ProcessingJob.perform_now("not a webhook")
    end

    assert_no_enqueued_jobs only: Webhukhs::ProcessingJob
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
