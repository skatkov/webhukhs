# frozen_string_literal: true

# ProcessingJob gets autoloaded, but the railtie of ActiveJob has to be there before the app boots
require "active_job/railtie"

module Webhukhs
  # Rails engine wiring routes, autoloading and generators for Webhukhs.
  class Engine < ::Rails::Engine
    isolate_namespace Webhukhs

    config.eager_load_namespaces << Webhukhs

    generators do
      require_relative "install_generator"
    end
  end
end
