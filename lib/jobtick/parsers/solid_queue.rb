# frozen_string_literal: true

require "yaml"

module JobTick
  module Parsers
    class SolidQueue
      RECURRING_FILE = "config/recurring.yml"

      def self.parse
        return [] unless File.exist?(RECURRING_FILE)

        yaml = YAML.load_file(RECURRING_FILE, aliases: true)
        env  = JobTick.config.environment

        tasks = yaml[env] || yaml["default"] || yaml
        return [] unless tasks.is_a?(Hash)

        tasks.each_with_object([]) do |(key, config), out|
          next unless config.is_a?(Hash)

          out << {
            key: "solid_queue.#{key}",
            schedule: config["schedule"],
            source: "solid_queue",
            task: config["class"]
          }
        end
      rescue StandardError => e
        JobTick.logger.warn("[JobTick] Solid Queue parser failed: #{e.message}")
        []
      end
    end
  end
end
