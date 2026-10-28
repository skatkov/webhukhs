# frozen_string_literal: true

# Public namespace for Webhukhs runtime and configuration.
module Webhukhs
  # Read-only administration for received webhooks.
  module Admin
    # Lists and shows stored webhooks. Read-only: the lifecycle belongs to Webhukhs::ProcessingJob.
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

      private

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
