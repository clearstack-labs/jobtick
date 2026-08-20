# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in jobtick.gemspec
gemspec

gem "irb"
gem "rake", "~> 13.0"

gem "rspec", "~> 3.13"
gem "webmock", "~> 3.23"

gem "rubocop", "~> 1.21"

# Real adapters, used in specs so the parsers are tested against actual APIs
# rather than hand-rolled stubs that can silently drift from reality.
gem "sidekiq", "~> 7.0", require: false
gem "sidekiq-cron", "~> 2.0", require: false
gem "whenever", "~> 1.0", require: false
