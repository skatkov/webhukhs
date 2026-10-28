# frozen_string_literal: true

module Webhukhs
  module Admin
    # Table-building helpers for the admin views.
    module ViewHelper
      # Renders a table inside a scroll container. Cells are `white-space: nowrap`, so one long
      # column would otherwise take the whole page sideways with it.
      #
      # @param columns [Array<String>] header cell contents
      # @param records [Array] rows to render
      # @yieldparam record [Object] one of the records
      # @yieldreturn [Array] cell contents for that record
      # @return [ActiveSupport::SafeBuffer]
      def admin_table(columns, records)
        rows = records.map do |record|
          tag.tr { safe_join(yield(record).map { |cell| tag.td(cell) }) }
        end
        rows = [tag.tr(tag.td("No records.", colspan: columns.length, class: "empty"))] if rows.empty?

        thead = tag.thead(tag.tr(safe_join(columns.map { |column| tag.th(column) })))
        tag.div(tag.table(safe_join([thead, tag.tbody(safe_join(rows))]), class: "admin-table"), class: "table-scroll")
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
