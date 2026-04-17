# frozen_string_literal: true

require "fileutils"
require "securerandom"
require "tmpdir"

hooks.register(:mutation_worker_process_start) do
  database = File.join(Dir.tmpdir, "webhukhs-mutant-#{Process.pid}-#{SecureRandom.hex(8)}.sqlite3")
  FileUtils.cp("development.sqlite3", database)
  ENV["DATABASE_URL"] = "sqlite3:#{database}"
  ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: database)
end
