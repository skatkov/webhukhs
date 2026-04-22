# frozen_string_literal: true

require "active_record"
require "action_pack"
require "action_controller"
require "rails"

module Test
  DEFAULT_DATABASE_PATH = File.expand_path("development.sqlite3", __dir__)
  DEFAULT_DATABASE_URL = "sqlite3:#{DEFAULT_DATABASE_PATH}"

  def self.database_url
    ENV.fetch("DATABASE_URL", DEFAULT_DATABASE_URL)
  end

  def self.database_path
    File.expand_path(database_url.delete_prefix("sqlite3:"))
  end

  def self.establish_database_connection
    database = database_path

    ENV["DATABASE_URL"] = database_url
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: database)
    ActiveRecord::Base.logger = Logger.new(nil)
  end

  def self.define_test_schema
    ActiveRecord::Schema.define do
      create_table "received_webhooks", force: :cascade do |t|
        t.string "handler_event_id", null: false
        t.string "handler_module_name", null: false
        t.string "status", default: "received", null: false
        t.binary "body", null: false
        t.json "request_headers", null: true
        t.datetime "created_at", null: false
        t.datetime "updated_at", null: false
        t.index ["handler_module_name", "handler_event_id"], name: "webhook_dedup_idx", unique: true
        t.index ["status"], name: "index_received_webhooks_on_status"
      end
    end
  end
end

Test.establish_database_connection
Test.define_test_schema

require_relative "../lib/webhukhs"
require_relative "test-webhook-handlers/webhook_test_handler"
require_relative "test-webhook-handlers/inactive_handler"
require_relative "test-webhook-handlers/invalid_handler"
require_relative "test-webhook-handlers/private_handler"
require_relative "test-webhook-handlers/failing_with_exposed_errors"
require_relative "test-webhook-handlers/failing_with_concealed_errors"
require_relative "test-webhook-handlers/extract_id_handler"

Webhukhs.configure do |config|
  config.active_handlers = {
    test: "WebhookTestHandler",
    inactive: "InactiveHandler",
    invalid: "InvalidHandler",
    private: "PrivateHandler",
    "failing-with-exposed-errors": "FailingWithExposedErrors",
    "failing-with-concealed-errors": "FailingWithConcealedErrors",
    extract_id: "ExtractIdHandler"
  }
end

class WebhukhsTestApp < Rails::Application
  config.logger = Logger.new(nil)
  config.autoload_paths << File.dirname(__FILE__) + "/test-webhook-handlers"
  config.root = __dir__
  config.eager_load = false
  config.consider_all_requests_local = true
  config.secret_key_base = "i_am_a_secret"
  config.active_support.cache_format_version = 7.1
  config.active_job.queue_adapter = :test
  config.hosts << ->(host) { true } # Permit all hosts

  routes.append do
    mount Webhukhs::Engine, at: "/webhukhs"
    post "/per-user-webhukhs/:user_id/:service_id" => "webhukhs/receive_webhooks#create"
  end
end

WebhukhsTestApp.initialize!

# run WebhukhsTestApp
