# frozen_string_literal: true

module Webhukhs
  module Admin
    # Wraps a Webhukhs::ReceivedWebhook with what the admin views need to display it.
    class ReceivedWebhookPresenter < SimpleDelegator
      # `received` and `processing` are on their way somewhere, the two failures are the rows
      # worth finding in a list. `skipped` is deliberate and stays uncolored
      STATUS_CLASSES = {
        "processed" => "status-ok",
        "error" => "status-bad",
        "failed_validation" => "status-bad",
        "received" => "status-waiting",
        "processing" => "status-waiting"
      }.freeze

      # Bodies larger than this are neither parsed nor shown in full - a browser asked to lay out
      # a few megabytes of pretty-printed JSON just hangs
      DISPLAY_LIMIT = 256 * 1024

      # CSS class coloring the status badge.
      #
      # @return [String]
      def status_class
        STATUS_CLASSES.fetch(status, "status-neutral")
      end

      # Whether the body is too large to display in full.
      #
      # @return [Boolean]
      def truncated?
        body.bytesize > DISPLAY_LIMIT
      end

      # The body as text, cut off at DISPLAY_LIMIT bytes. The body is stored as raw bytes and is not
      # necessarily UTF-8, so anything that does not decode (including a character the cut went through)
      # gets replaced with U+FFFD instead of blowing up the view.
      #
      # @return [String]
      def body_text
        String.new(body.byteslice(0, DISPLAY_LIMIT), encoding: Encoding::UTF_8).scrub
      end

      # Pretty-printed body, if the body is valid JSON.
      #
      # @return [String, nil]
      def pretty_json
        JSON.pretty_generate(JSON.parse(body_text))
      rescue JSON::ParserError
        nil
      end

      # Stored request headers sorted by name, with structured values (the path parameters) as JSON.
      #
      # @return [Array<Array<String>>] name and value pairs
      def header_rows
        request_headers.to_h.sort.map do |name, value|
          [name, value.instance_of?(String) ? value : value.to_json]
        end
      end
    end
  end
end
