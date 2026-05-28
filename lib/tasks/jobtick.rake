# frozen_string_literal: true

namespace :jobtick do
  desc "Sync discovered jobs with jobtick.app"
  task sync: :environment do
    require "jobtick/parsers/whenever"
    require "jobtick/parsers/solid_queue"
    require "jobtick/parsers/sidekiq"
    require "jobtick/registry"

    monitors = JobTick::Registry.sync
    count    = monitors&.length || 0
    puts "[JobTick] Synced #{count} monitor(s)"
  end

  namespace :whenever do
    desc "Print the line to add to config/schedule.rb to enable JobTick heartbeat injection"
    task :setup do
      puts <<~RUBY
        # Add to config/schedule.rb to enable JobTick heartbeat injection for all Whenever jobs:

        JobTick::WheneverSetup.install!(self)

        # This overrides the built-in runner, rake, and command job types so that
        # every scheduled job automatically sends started/completed/failed heartbeats.
        # No per-job changes are required.
        #
        # If jobtick is not already loaded via your Rails environment, add:
        #   require "jobtick/whenever_setup"
        # before the install! call.
      RUBY
    end
  end
end
