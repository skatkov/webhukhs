# frozen_string_literal: true

require "active_job/railtie"

module Webhukhs
  class ProcessingJob < ActiveJob::Base
    class InvalidWebhookArgument < StandardError; end

    discard_on ActiveJob::DeserializationError, InvalidWebhookArgument do |_job, error|
      Webhukhs.instrument(operation: :process, outcome: :discarded, severity: :error, error: error)
    end

    # @param webhook [Webhukhs::ReceivedWebhook] webhook record to process
    # @return [void]
    def perform(webhook)
      raise InvalidWebhookArgument, "ProcessingJob received nil webhook argument" if webhook.nil?
      unless webhook.instance_of?(ReceivedWebhook)
        raise InvalidWebhookArgument, "ProcessingJob expected Webhukhs::ReceivedWebhook, got #{webhook.class}"
      end

      event = {operation: :process, severity: :info, webhook_id: webhook.id, handler_class: webhook.handler_module_name}

      webhook.with_lock do
        unless webhook.received?
          Webhukhs.instrument(event.merge(outcome: :skipped))
          return
        end

        webhook.processing!
      end

      if webhook.handler.valid?(webhook.request)
        Webhukhs.instrument(**event.merge(outcome: :started))
        webhook.handler.process(webhook)
        webhook.processed! if webhook.processing?
        Webhukhs.instrument(**event.merge(outcome: :completed))
      else
        Webhukhs.instrument(**event.merge(outcome: :validation_failed))
        webhook.failed_validation!
      end
    rescue => error
      if webhook.respond_to?(:error!)
        webhook.error!
        Webhukhs.instrument(**event.merge(outcome: :error, severity: :error, error: error))
      end
      raise
    end
  end
end
