# frozen_string_literal: true

module JobTick
  class Registry
    def self.sync
      monitors = [
        Parsers::Whenever.parse,
        Parsers::SolidQueue.parse,
        Parsers::Sidekiq.parse
      ].flatten.compact

      map = {}
      monitors.each { |m| map[m[:task]] = m[:key] if m[:task] }
      JobTick.monitor_map = map.freeze

      return [] if monitors.empty?

      app_name = Rails.application.class.module_parent_name if defined?(Rails)
      options  = { app_name: app_name }
      options[:prune] = true if JobTick.config.prune
      JobTick.client.register(monitors, **options)
      monitors
    end
  end
end
