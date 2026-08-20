# frozen_string_literal: true

module JobTick
  class Railtie < Rails::Railtie
    # Processes where a boot-time sync would be pure waste: `rails console`,
    # any rake task, and `rails runner` — the latter matters most, since
    # WheneverSetup shells out through `bundle exec rails runner` on every
    # cron tick, so without this a minutely job would pay a full sync POST
    # every minute just to boot.
    ONE_OFF_PROCESSES = %w[rake].freeze

    initializer "jobtick.sync_registry" do
      ActiveSupport.on_load(:after_initialize) do
        next unless JobTick.config.enabled

        require_relative "parsers/whenever"
        require_relative "parsers/solid_queue"
        require_relative "parsers/sidekiq"
        require_relative "registry"
        require_relative "hooks/active_job"
        require_relative "middleware/sidekiq"

        JobTick::Registry.sync(sync: false) if JobTick::Railtie.sync_on_boot?

        ::ActiveJob::Base.include(JobTick::Hooks::ActiveJob) if defined?(::ActiveJob::Base)
        JobTick::Middleware::Sidekiq.install if defined?(::Sidekiq)
      end
    end

    rake_tasks do
      load File.expand_path("../tasks/jobtick.rake", __dir__)
    end

    def self.sync_on_boot?
      return false unless JobTick.config.sync_on_boot

      !one_off_process?
    end

    # `Rails::Console` / `Rails::Command::RunnerCommand` / `Rails::Command::RakeCommand`
    # are only defined when boot was reached via `bin/rails console|runner|<task>` — the
    # command file that defines each constant has to be loaded before boot can start.
    # A plain `bundle exec rake <task>` never loads railties' command layer at all, so
    # it's caught by the $PROGRAM_NAME basename check instead.
    def self.one_off_process?
      return true if defined?(Rails::Console)
      return true if defined?(Rails::Command::RunnerCommand)
      return true if defined?(Rails::Command::RakeCommand)

      ONE_OFF_PROCESSES.include?(File.basename($PROGRAM_NAME.to_s, ".*"))
    end
  end
end
