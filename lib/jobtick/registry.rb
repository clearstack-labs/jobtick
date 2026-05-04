# frozen_string_literal: true

module JobTick
  class Registry
    def self.sync
      monitors = [
        Parsers::Whenever.parse,
        Parsers::SolidQueue.parse,
        Parsers::Sidekiq.parse
      ].flatten.compact

      return [] if monitors.empty?

      JobTick.client.register(monitors)
      monitors
    end
  end
end
