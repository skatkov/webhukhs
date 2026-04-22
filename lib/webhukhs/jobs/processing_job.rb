# frozen_string_literal: true

require "active_job/railtie"

module Webhukhs
  # Background job that validates and processes a persisted webhook.
  class ProcessingJob < ActiveJob::Base
    # Raised when the job receives an invalid webhook argument.
    class InvalidWebhookArgument < StandardError; end

    discard_on ActiveJob::DeserializationError, InvalidWebhookArgument do |job, error|
      Rails.error.report(error, context: {
        job_id: job.job_id,
        arguments: job.arguments.map(&:inspect)
      }, severity: :error)
    end

    # Runs webhook validation and processing lifecycle.
    #
    # @param webhook [Webhukhs::ReceivedWebhook] webhook record to process
    # @return [void]
    def perform(webhook)
      raise InvalidWebhookArgument, "ProcessingJob received nil webhook argument" if webhook.nil?
      unless webhook.instance_of?(ReceivedWebhook)
        raise InvalidWebhookArgument, "ProcessingJob expected Webhukhs::ReceivedWebhook, got #{webhook.class}"
      end

      webhook.with_lock do
        return unless webhook.received?

        webhook.processing!
      end

      if webhook.handler.valid?(webhook.request)
        webhook.handler.process(webhook)
        webhook.processed! if webhook.processing?
      else
        webhook.failed_validation!
      end
    rescue StandardError
      webhook.error! if webhook.respond_to?(:error!)
      raise
    end
  end
end
