# frozen_string_literal: true

require "active_job/railtie"

module Webhukhs
  # Background job that validates and processes a persisted webhook.
  class ProcessingJob < ActiveJob::Base
    # Raised when the job receives an invalid webhook argument.
    class InvalidWebhookArgument < StandardError; end

    discard_on ActiveJob::DeserializationError, InvalidWebhookArgument do |_job, error|
      Webhukhs.instrument(operation: :process, outcome: :discarded, severity: :error, error: error)
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
        unless webhook.received?
          Webhukhs.instrument(operation: :process, outcome: :skipped, severity: :info, webhook_id: webhook.id, handler_class: webhook.handler_module_name)
          return
        end

        webhook.processing!
      end

      if webhook.handler.valid?(webhook.request)
        Webhukhs.instrument(operation: :process, outcome: :started, severity: :info, webhook_id: webhook.id, handler_class: webhook.handler_module_name)
        webhook.handler.process(webhook)
        webhook.processed! if webhook.processing?
        Webhukhs.instrument(operation: :process, outcome: :completed, severity: :info, webhook_id: webhook.id, handler_class: webhook.handler_module_name)
      else
        Webhukhs.instrument(operation: :process, outcome: :validation_failed, severity: :info, webhook_id: webhook.id, handler_class: webhook.handler_module_name)
        webhook.failed_validation!
      end
    rescue => error
      if webhook.respond_to?(:error!)
        webhook.error!
        Webhukhs.instrument(operation: :process, outcome: :error, severity: :error, error: error, webhook_id: webhook.id, handler_class: webhook.handler_module_name)
      end
      raise
    end
  end
end
