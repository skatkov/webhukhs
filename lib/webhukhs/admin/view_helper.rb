# frozen_string_literal: true

module Webhukhs
  module Admin
    # Table-building helpers for the admin views.
    module ViewHelper
      # Canonical UUID format, independent of UUID version.
      UUID_RE = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

      # Displays the first 4 and last 4 UUID characters, keeping the full ID on hover.
      #
      # @param uuid_str [String] ID to display
      # @return [String, ActiveSupport::SafeBuffer]
      def short_id(uuid_str)
        return uuid_str unless UUID_RE.match?(uuid_str)

        shortened = [uuid_str.first(4), uuid_str.last(4)].join("..")
        content_tag(:abbr, shortened, title: uuid_str)
      end

      # One table row, each cell wrapped in a `td`.
      #
      # Separate from #admin_table, which takes rows rather than building them, so that a row can
      # also be rendered on its own - the retry of a webhook answers with its row alone, for the
      # listing to put in place of the one that was there.
      #
      # @param cells [Array] cell contents
      # @return [ActiveSupport::SafeBuffer]
      def admin_row(cells)
        tag.tr { safe_join(cells.map { |cell| tag.td(cell) }) }
      end

      # Renders a table inside a scroll container. Cells are `white-space: nowrap`, so one long
      # column would otherwise take the whole page sideways with it.
      #
      # Rows can come either way: with a block, each record is turned into a row of the cells the
      # block returns, and without one the records are the rows themselves - already rendered, by
      # #admin_row or by a partial. The listing needs the second, since its rows carry attributes
      # of their own and one of them is also rendered on its own when a webhook is retried.
      #
      # @param columns [Array<String>] header cell contents
      # @param records [Array] rows to render, or records to build rows from
      # @yieldparam record [Object] one of the records
      # @yieldreturn [Array] cell contents for that record
      # @return [ActiveSupport::SafeBuffer]
      def admin_table(columns, records)
        rows = block_given? ? records.map { |record| admin_row(yield(record)) } : records
        rows = [tag.tr(tag.td("No records.", colspan: columns.length, class: "empty"))] if rows.empty?

        thead = tag.thead(tag.tr(safe_join(columns.map { |column| tag.th(column) })))
        tag.div(tag.table(safe_join([thead, tag.tbody(safe_join(rows))]), class: "admin-table"), class: "table-scroll")
      end

      # The id of the row a webhook is listed in, so that the listing can find it again when the
      # webhook is retried and its row comes back changed.
      #
      # @param webhook [Webhukhs::Admin::ReceivedWebhookPresenter]
      # @return [String]
      def received_webhook_row_id(webhook)
        "webhook-#{webhook.id}"
      end

      # The retry button, as a form of its own - disabled rather than hidden for a webhook that
      # cannot be retried, so that it does not move about between statuses.
      #
      # The block form of `button_to`, so that this is a `button` whatever the host application has
      # `button_to_generates_button_tag` set to.
      #
      # @param webhook [Webhukhs::Admin::ReceivedWebhookPresenter]
      # @return [ActiveSupport::SafeBuffer]
      def retry_button(webhook)
        button_to(retry_received_webhook_path(webhook), class: "btn-retry", disabled: !webhook.retryable?, title: webhook.retry_title) { "Retry" }
      end

      # ID column header linking to the index with the sort direction reversed.
      #
      # @param direction [String] current direction, "asc" or "desc"
      # @return [ActiveSupport::SafeBuffer]
      def sort_link(direction:)
        next_direction = (direction == "desc") ? "asc" : "desc"
        query = request.query_parameters.except("page", "sort").merge("direction" => next_direction)
        label = safe_join(["Id", tag.span((direction == "asc") ? "▲" : "▼", class: "sort-arrow")], " ")
        link_to(label, query, class: "sort-link")
      end

      # Button copying a value to the clipboard (see admin.js).
      #
      # @param value [String] text to copy
      # @return [ActiveSupport::SafeBuffer]
      def copy_button(value)
        tag.button(class: "btn-copy", type: "button", title: "Copy to clipboard", data: {copy: value})
      end
    end
  end
end
