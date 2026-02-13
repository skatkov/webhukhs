# frozen_string_literal: true

require_relative "lib/webhukhs/version"

Gem::Specification.new do |spec|
  spec.name = "webhukhs"
  spec.version = Webhukhs::VERSION
  spec.authors = ["Stanislav Katkov"]
  spec.email = ["github@skatkov.com"]

  spec.summary = "Webhooks processing engine for Rails applications"
  spec.description = "Webhukhs is a Rails engine for processing webhooks from various services. Engine saves webhook in database first and later processes in async job."
  spec.homepage = "https://github.com/skatkov/webhukhs"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "https://github.com/skatkov/webhukhs/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ .git .github appveyor Gemfile])
    end
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", ">= 7.0"
  spec.add_dependency "state_machine_enum"
  spec.add_development_dependency "appraisal"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "standard"
  spec.add_development_dependency "magic_frozen_string_literal"
  spec.add_development_dependency "minitest", "~> 5.0"
end
