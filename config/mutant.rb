# frozen_string_literal: true

require "fileutils"

project_root = File.expand_path("..", __dir__)
template_database = File.expand_path("test/development.sqlite3", project_root)
worker_database_dir = File.expand_path("tmp/mutant", project_root)

disconnect_database = lambda do
  next unless defined?(ActiveRecord::Base)
  next unless ActiveRecord::Base.connected?

  ActiveRecord::Base.connection_pool.disconnect!
end

isolate_database = lambda do |index:|
  disconnect_database.call
  FileUtils.mkdir_p(worker_database_dir)

  database = File.join(worker_database_dir, "worker-#{index}-#{Process.pid}.sqlite3")
  FileUtils.cp(template_database, database)

  ENV["DATABASE_URL"] = "sqlite3:#{database}"
  ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: database)
end

hooks.register(:setup_integration_post) do
  disconnect_database.call
end

hooks.register(:test_worker_process_start) do |index:|
  isolate_database.call(index: index)
end

hooks.register(:mutation_worker_process_start) do |index:|
  isolate_database.call(index: index)
end
