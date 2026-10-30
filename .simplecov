SimpleCov.cover "lib/**/*.rb"
SimpleCov.skip "lib/webhukhs/install_generator.rb"
SimpleCov.skip "lib/webhukhs/templates"
SimpleCov.skip "lib/webhukhs/version.rb" # Bundler loads this before coverage starts.
SimpleCov.track_tests

SimpleCov.coverage :line do
  minimum 100
  minimum 100, per: :file
end

SimpleCov.coverage :branch do
  minimum 100
  minimum 100, per: :file
end
