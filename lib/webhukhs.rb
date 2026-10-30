# frozen_string_literal: true

require "active_support"
require "active_support/core_ext/class/attribute"
require "active_support/core_ext/numeric/bytes"
require_relative "webhukhs/version"

# Public namespace for Webhukhs runtime and configuration.
module Webhukhs
  extend ActiveSupport::Autoload

  eager_autoload do
    autoload :ReceiveWebhooksController, "webhukhs/controllers/receive_webhooks_controller"
    autoload :ProcessingJob, "webhukhs/jobs/processing_job"
    autoload :ReceivedWebhook, "webhukhs/models/received_webhook"
    autoload :BaseHandler, "webhukhs/base_handler"
  end

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
end

# Holds runtime configuration for Webhukhs.
class Webhukhs::Configuration
  class_attribute :processing_job_class, default: "Webhukhs::ProcessingJob"
  class_attribute :active_handlers, default: {}
  class_attribute :error_context, default: {}
  class_attribute :request_body_size_limit, default: 512.kilobytes
end

require_relative "webhukhs/engine"
# The engines have to be defined before the app boots, so that Rails runs their initializers -
# a `mount` in config/routes.rb comes too late for that
require_relative "webhukhs/admin"
