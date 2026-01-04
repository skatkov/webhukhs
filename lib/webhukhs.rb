# frozen_string_literal: true

require_relative "webhukhs/version"
require_relative "webhukhs/engine"
require_relative "webhukhs/jobs/processing_job"
require "active_support/configurable"

module Webhukhs
  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configure
    yield configuration
  end
end

class Webhukhs::Configuration
  include ActiveSupport::Configurable

  config_accessor(:processing_job_class, default: Webhukhs::ProcessingJob)
  config_accessor(:active_handlers, default: {})
  config_accessor(:error_context, default: {})
  config_accessor(:request_body_size_limit, default: 512.kilobytes)
end
