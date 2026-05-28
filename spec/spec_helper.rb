# frozen_string_literal: true

require "webmock/rspec"
require "jobtick"

# Eagerly load lazily-required files so all specs can reference the constants.
require "jobtick/parsers/whenever"
require "jobtick/parsers/solid_queue"
require "jobtick/parsers/sidekiq"
require "jobtick/registry"
require "jobtick/hooks/active_job"
require "jobtick/middleware/sidekiq"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.order = :random
  Kernel.srand config.seed

  config.before do
    JobTick.reset!
    WebMock.reset!
    JobTick::Dispatcher.synchronous = true
  end
end

# Silence the default stdout logger in specs
module JobTick
  def self.logger
    Logger.new(IO::NULL)
  end
end
