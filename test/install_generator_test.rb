# frozen_string_literal: true

require "test_helper"
require "rails/generators/test_case"
require "webhukhs/install_generator"
require "tmpdir"

class InstallGeneratorTest < Rails::Generators::TestCase
  cover "Webhukhs::InstallGenerator*"

  tests Webhukhs::InstallGenerator

  setup do
    root = File.expand_path("../tmp", __dir__)
    FileUtils.mkdir_p(root)
    self.destination_root = Dir.mktmpdir("install_generator-", root)
  end

  teardown { FileUtils.remove_entry(destination_root) }

  test "generates the table, headers, listing index and initializer for new installations" do
    run_generator

    assert_migration "db/migrate/create_webhukhs_tables.rb"
    assert_migration "db/migrate/add_headers_to_webhukhs_webhooks.rb"
    assert_migration "db/migrate/add_index_to_webhukhs_webhooks.rb" do |content|
      assert_includes content, "class AddIndexToWebhukhsWebhooks < ActiveRecord::Migration[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
    end
    assert_file "config/initializers/webhukhs.rb"
  end

  test "generates a reversible index that avoids sorting the default listing" do
    run_generator
    load Dir[File.join(destination_root, "db/migrate/*_add_index_to_webhukhs_webhooks.rb")].fetch(0)
    migration = AddIndexToWebhukhsWebhooks.new
    connection = ActiveRecord::Base.connection

    migration.migrate(:up)

    assert connection.index_exists?(:received_webhooks, [:created_at, :id])
    plan = connection.select_rows(<<~SQL).flatten.join(" ")
      EXPLAIN QUERY PLAN SELECT received_webhooks.* FROM received_webhooks
      ORDER BY created_at DESC, id DESC LIMIT 51 OFFSET 50
    SQL
    assert_includes plan, "USING INDEX index_received_webhooks_on_created_at_and_id"
    refute_includes plan, "TEMP B-TREE"
  ensure
    migration&.migrate(:down)
    assert_not connection.index_exists?(:received_webhooks, [:created_at, :id]) if connection
  end

  test "upgrades existing installations without replacing migrations or configuration" do
    migrate_path = File.join(destination_root, "db/migrate")
    initializer_path = File.join(destination_root, "config/initializers")
    FileUtils.mkdir_p([migrate_path, initializer_path])
    File.write(File.join(migrate_path, "20200101000000_create_webhukhs_tables.rb"), "# Existing table migration\n")
    File.write(File.join(migrate_path, "20200101000001_add_headers_to_webhukhs_webhooks.rb"), "# Existing headers migration\n")
    File.write(File.join(initializer_path, "webhukhs.rb"), "# Custom handlers\n")

    2.times { run_generator ["--skip"] }

    assert_equal 3, Dir[File.join(migrate_path, "*.rb")].length
    assert_migration "db/migrate/add_index_to_webhukhs_webhooks.rb"
    assert_file "db/migrate/20200101000000_create_webhukhs_tables.rb", "# Existing table migration\n"
    assert_file "db/migrate/20200101000001_add_headers_to_webhukhs_webhooks.rb", "# Existing headers migration\n"
    assert_file "config/initializers/webhukhs.rb", "# Custom handlers\n"
  end
end
