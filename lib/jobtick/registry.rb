# frozen_string_literal: true

module JobTick
  class Registry
    def self.sync
      monitors = [
        Parsers::Whenever.parse,
        Parsers::SolidQueue.parse,
        Parsers::Sidekiq.parse
      ].flatten.compact

      JobTick.monitor_map = monitors.each_with_object({}) do |m, map|
        map[m[:task]] = m[:key] if m[:task]
      end

      return [] if monitors.empty?

      app_name = Rails.application.class.module_parent_name if defined?(Rails)
      options  = { app_name: app_name }
      options[:prune] = true if JobTick.config.prune
      JobTick.client.register(monitors, **options)
      monitors
    end
  end
end
