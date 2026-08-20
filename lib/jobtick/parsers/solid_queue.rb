# frozen_string_literal: true

require "yaml"

module JobTick
  module Parsers
    class SolidQueue
      RECURRING_FILE = "config/recurring.yml"

      def self.parse
        return [] unless File.exist?(recurring_path)

        yaml = YAML.load_file(recurring_path, aliases: true)
        return [] unless yaml.is_a?(Hash)

        tasks = resolve_tasks(yaml)
        return [] if tasks.empty?

        class_tasks, command_only = tasks.partition { |_, config| task_class?(config) }
        warn_command_only(command_only) if command_only.any?

        class_tasks.map { |key, config| monitor_for(key, config) }
      rescue StandardError => e
        JobTick.logger.warn("[JobTick] Solid Queue parser failed: #{e.message}")
        []
      end

      # recurring.yml is either flat (task name => task config at the top
      # level) or environment-scoped (environment name => { task name =>
      # task config }). Distinguish by whether any top-level value actually
      # looks like a task, rather than assuming the current environment is
      # always present — a document scoped to "production"/"development"
      # read under "staging" used to fall through to `yaml` itself and
      # register every *environment name* as an unpingable monitor.
      def self.resolve_tasks(yaml)
        return yaml if yaml.any? { |_, v| task?(v) }

        env = JobTick.config.environment
        scoped = yaml[env] || yaml["default"]
        return scoped if scoped.is_a?(Hash)

        JobTick.logger.warn(
          "[JobTick] #{RECURRING_FILE} is environment-scoped but has no entry for " \
          "\"#{env}\" (or \"default\"); no Solid Queue monitors registered"
        )
        {}
      end
      private_class_method :resolve_tasks

      def self.task?(value)
        value.is_a?(Hash) && (value.key?("class") || value.key?("command"))
      end
      private_class_method :task?

      def self.task_class?(value)
        value.is_a?(Hash) && value.key?("class")
      end
      private_class_method :task_class?

      def self.monitor_for(key, config)
        { key: "solid_queue.#{key}", schedule: config["schedule"], source: "solid_queue", task: config["class"] }
      end
      private_class_method :monitor_for

      # command: tasks run a raw shell command rather than a Ruby job class,
      # so there's no ActiveJob/Sidekiq hook to ping them from — unlike
      # Whenever, Solid Queue gives us no shell wrapping point either.
      # Registering them anyway would create monitors that alert as
      # permanently down, so we skip them and say why once.
      def self.warn_command_only(command_only)
        keys = command_only.map(&:first).join(", ")
        JobTick.logger.warn(
          "[JobTick] #{RECURRING_FILE} declares command-based task(s) (#{keys}) which have no " \
          "Ruby class to hook into; JobTick cannot monitor them automatically"
        )
      end
      private_class_method :warn_command_only

      def self.recurring_path
        File.expand_path(RECURRING_FILE, JobTick.root)
      end
      private_class_method :recurring_path
    end
  end
end
