# frozen_string_literal: true

require_relative "lib/jobtick/version"

Gem::Specification.new do |spec|
  spec.name = "jobtick"
  spec.version = JobTick::VERSION
  spec.authors = ["Clearstack Labs"]
  spec.email = ["hello@clearstacklabs.com"]

  spec.summary = "Rails job monitoring for Whenever, Solid Queue, and Sidekiq"
  spec.description = "Auto-discovers and monitors all scheduled jobs in your Rails app. Zero configuration per job."
  spec.homepage = "https://jobtick.app"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/clearstack-labs/jobtick"
  spec.metadata["changelog_uri"] = "https://github.com/clearstack-labs/jobtick/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ spec/ .github/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "logger", ">= 1.6"
end
