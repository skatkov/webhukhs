# frozen_string_literal: true

require "active_job/railtie"

module Webhukhs
  class ProcessingJob < ActiveJob::Base
    class InvalidWebhookArgument < StandardError; end

    discard_on ActiveJob::DeserializationError do |job, error|
      Rails.error.report(error, context: {
        job_id: job.job_id,
        arguments: job.arguments.map(&:inspect)
      }, severity: :error)
    end

    discard_on InvalidWebhookArgument do |job, error|
      Rails.error.report(error, context: {
        job_id: job.job_id,
        arguments: job.arguments.map(&:inspect)
      }, severity: :error)
    end

    def perform(webhook)
      raise InvalidWebhookArgument, "ProcessingJob received nil webhook argument" if webhook.nil?
      unless webhook.is_a?(Webhukhs::ReceivedWebhook)
        raise InvalidWebhookArgument, "ProcessingJob expected Webhukhs::ReceivedWebhook, got #{webhook.class}"
      end

      webhook_details_for_logs = "Webhukhs::ReceivedWebhook#%s (handler: %s)" % [webhook.id, webhook.handler]
      webhook.with_lock do
        unless webhook.received?
          logger.info { "#{webhook_details_for_logs} is being processed in a different job or has been processed already, skipping." }
          return
        end
        webhook.processing!
      end

      if webhook.handler.valid?(webhook.request)
        logger.info { "#{webhook_details_for_logs} starting to process" }
        webhook.handler.process(webhook)
        webhook.processed! if webhook.processing?
        logger.info { "#{webhook_details_for_logs} processed" }
      else
        logger.info { "#{webhook_details_for_logs} did not pass validation by the handler. Marking it `failed_validation`." }
        webhook.failed_validation!
      end
    rescue => e
      webhook.error!
      raise e
    end
  end
end
