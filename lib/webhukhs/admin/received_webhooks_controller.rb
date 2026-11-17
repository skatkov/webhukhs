# frozen_string_literal: true

# Public namespace for Webhukhs runtime and configuration.
module Webhukhs
  # Read-only administration for received webhooks.
  module Admin
    # Lists and shows stored webhooks, and puts the ones that did not get processed back in line.
    # Beyond that retry the lifecycle belongs to Webhukhs::ProcessingJob.
    class ReceivedWebhooksController < ApplicationController
      # Webhooks per index page
      PAGE_SIZE = 50

      helper_method :handler_options, :status_options

      # Renders a filtered, sorted page of webhooks.
      #
      # @return [void]
      def index
        @direction = (params[:direction] == "asc") ? "asc" : "desc"
        @page = [params[:page].to_i, 1].max

        filters = {handler_module_name: params[:handler], status: params[:status]}.compact_blank

        rows = ReceivedWebhook
          .where(filters)
          .order(id: @direction)
          .offset((@page - 1) * PAGE_SIZE)
          .limit(PAGE_SIZE + 1)
        @next_page = @page + 1 if rows.length > PAGE_SIZE
        @webhooks = rows.first(PAGE_SIZE).map { |webhook| ReceivedWebhookPresenter.new(webhook) }
      end

      # Renders one webhook with its body and headers.
      #
      # @return [void]
      def show
        @webhook = ReceivedWebhookPresenter.new(ReceivedWebhook.find(params.fetch(:id)))
      end

      # Set by admin.js on the retry it sends from the listing, where the answer wanted is the row
      # rather than a page to go to
      ROW_REQUEST_HEADER = "X-Webhukhs-Row"

      # Puts one webhook back in line for processing.
      #
      # Answers with the webhook's row for a retry pressed in the listing, so the listing can put it
      # in place of the one that was there - and with a redirect to the webhook otherwise, which is
      # what a plain form submit (no JavaScript, or the button on the webhook's own page) wants.
      #
      # @return [void]
      def retry
        webhook = ReceivedWebhook.find(params.fetch(:id))
        webhook.retry!
        return render_row(webhook) if row_requested?

        redirect_to webhook, notice: "Webhook queued for processing again."
      rescue StateMachineEnum::InvalidTransition
        # The button is disabled for a webhook that cannot be retried, so getting here means the
        # status changed under whoever pressed it - or that the request did not come from the page.
        # The row that goes back says what the status actually is, which is the answer either way.
        return render_row(webhook) if row_requested?

        redirect_to webhook, alert: "This webhook is #{webhook.status} and cannot be retried."
      end

      private

      # @return [Boolean]
      def row_requested?
        request.headers.key?(ROW_REQUEST_HEADER)
      end

      # The webhook as one row of the listing, and nothing else - no layout, no page around it.
      #
      # @param webhook [Webhukhs::ReceivedWebhook]
      # @return [void]
      def render_row(webhook)
        render partial: "received_webhook", locals: {webhook: ReceivedWebhookPresenter.new(webhook)}
      end

      # The configured handlers rather than a DISTINCT over the table, so that a handler which has
      # not received anything yet can still be picked - "nothing arrived" is an answer too.
      #
      # @return [Array<String>] handler class names
      def handler_options
        Webhukhs.configuration.active_handlers.values.map(&:to_s).uniq.sort
      end

      # Statuses a webhook can be in, to filter by.
      #
      # @return [Hash{String => String}]
      def status_options
        ReceivedWebhook.statuses
      end
    end
  end
end
