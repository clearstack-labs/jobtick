# frozen_string_literal: true

module JobTick
  class Registry
    # sync: true blocks the caller until the register POST completes (used by
    # `rake jobtick:sync`, whose printed count must be truthful). The railtie
    # boot hook passes sync: false so a slow or unreachable API cannot delay
    # every process boot.
    def self.sync(sync: true)
      monitors = [
        Parsers::Whenever.parse,
        Parsers::SolidQueue.parse,
        Parsers::Sidekiq.parse
      ].flatten.compact

      JobTick.monitor_map = build_monitor_map(monitors)

      return [] if monitors.empty?

      app_name = Rails.application.class.module_parent_name if defined?(Rails)
      options  = { app_name: app_name, sync: sync }
      options[:prune] = true if JobTick.config.prune
      JobTick.client.register(monitors, **options)
      monitors
    end

    # Builds the class-name => monitor-key map the ActiveJob hook and Sidekiq
    # middleware use to find a job's monitor. Two monitors can legitimately
    # target the same class (e.g. the same recurring job class scheduled
    # twice with different arguments) — that's a real config ambiguity, not a
    # crash, so we log it and keep the first mapping rather than silently
    # letting the second overwrite it.
    def self.build_monitor_map(monitors)
      map = {}

      monitors.each do |monitor|
        task = monitor[:task]
        next unless task

        if map.key?(task)
          JobTick.logger.warn(
            "[JobTick] Multiple monitors target #{task} (#{map[task]} and #{monitor[:key]}); " \
            "only #{map[task]} will receive pings for it"
          )
          next
        end

        map[task] = monitor[:key]
      end

      map.freeze
    end
    private_class_method :build_monitor_map
  end
end
