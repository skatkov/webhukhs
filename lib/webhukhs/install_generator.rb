# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module Webhukhs
  # Rails generator used for setting up Webhukhs in a Rails application.
  # Run it with +bin/rails g webhukhs:install+ in your console.
  class InstallGenerator < Rails::Generators::Base
    include ActiveRecord::Generators::Migration

    source_root File.expand_path("../templates", __FILE__)

    # Creates migration files required by Webhukhs tables.
    #
    # @return [void]
    def create_migration_file
      migration_template "create_webhukhs_tables.rb.erb", File.join(db_migrate_path, "create_webhukhs_tables.rb")
      migration_template "add_headers_to_webhukhs_webhooks.rb.erb", File.join(db_migrate_path, "add_headers_to_webhukhs_webhooks.rb")
    end

    # Copies initializer file into host application.
    #
    # @return [void]
    def copy_files
      template "webhukhs.rb", File.join("config", "initializers", "webhukhs.rb")
    end

    private

    # Declares ActiveRecord migration version.
    #
    # @return [String]
    def migration_version
      "[#{ActiveRecord::VERSION::STRING.to_f}]"
    end
  end
end
