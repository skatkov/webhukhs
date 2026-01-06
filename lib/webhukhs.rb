# frozen_string_literal: true

require_relative "webhukhs/version"
require_relative "webhukhs/engine"
require_relative "webhukhs/jobs/processing_job"
require "active_support/core_ext/class/attribute"

module Webhukhs
  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configure
    yield configuration
  end
end

class Webhukhs::Configuration
  class_attribute :processing_job_class, default: Webhukhs::ProcessingJob
  class_attribute :active_handlers, default: {}
  class_attribute :error_context, default: {}
  class_attribute :request_body_size_limit, default: 512.kilobytes
end
