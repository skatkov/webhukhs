# frozen_string_literal: true

require_relative "webhukhs/version"
require_relative "webhukhs/engine"
require_relative "webhukhs/jobs/processing_job"
require "active_support/core_ext/class/attribute"
require "active_support/notifications"

# Public namespace for Webhukhs runtime and configuration.
module Webhukhs
  # Returns singleton configuration object.
  #
  # @return [Webhukhs::Configuration]
  def self.configuration
    @configuration ||= Configuration.new
  end

  # Yields global configuration object for setup.
  #
  # @yieldparam configuration [Webhukhs::Configuration]
  # @return [void]
  def self.configure
    yield configuration
  end

  # Emits Webhukhs observability events.
  #
  # @param payload [Hash] structured event payload
  # @return [void]
  def self.instrument(payload)
    ActiveSupport::Notifications.instrument("webhukhs.event", payload)
  end
end

# Holds runtime configuration for Webhukhs.
class Webhukhs::Configuration
  class_attribute :processing_job_class, default: Webhukhs::ProcessingJob
  class_attribute :active_handlers, default: {}
  class_attribute :request_body_size_limit, default: 512.kilobytes
end
