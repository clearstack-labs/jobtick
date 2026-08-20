# frozen_string_literal: true

require_relative "../parsers"

module JobTick
  module Parsers
    class Whenever
      SCHEDULE_FILE = "config/schedule.rb"
      JOBTICK_KEY_RE = /JOBTICK_KEY=(\S+)/

      # Whenever::JobList has no public reader for its parsed jobs (only
      # attr_reader :roles), and its internal @jobs is a private, nested
      # [mailto][time_scope] => [Job] structure with no [] accessor on Job
      # either. The only stable, public surface is #generate_cron_output —
      # the same text Whenever writes to the crontab. We scan that instead
      # of reaching into private internals.
      #
      # This only finds anything once JobTick::WheneverSetup.install!(self)
      # has been added to config/schedule.rb: that's what stamps a literal
      # JOBTICK_KEY=<key> into each job's command, which is what we key off
      # of here. That also guarantees the registered key and the pinged key
      # can never drift apart — they're the same literal.
      def self.parse
        return [] unless whenever_available?
        return [] unless File.exist?(schedule_path)

        schedule = ::Whenever::JobList.new(file: schedule_path)
        monitors = schedule.generate_cron_output.to_s.each_line.filter_map { |line| monitor_from_line(line) }

        warn_if_not_installed if monitors.empty?
        monitors
      rescue StandardError => e
        JobTick.logger.warn("[JobTick] Whenever parser failed: #{e.message}")
        []
      end

      def self.monitor_from_line(line)
        key = line[JOBTICK_KEY_RE, 1]
        return nil unless key

        { key: key, schedule: cron_fields(line), source: "whenever", task: nil }
      end
      private_class_method :monitor_from_line

      def self.cron_fields(line)
        line = line.strip
        return line[/\A@\S+/] if line.start_with?("@")

        line.split(/\s+/, 6).first(5).join(" ")
      end
      private_class_method :cron_fields

      def self.whenever_available?
        return true if defined?(::Whenever::JobList)

        require "whenever"
        true
      rescue LoadError
        false
      end
      private_class_method :whenever_available?

      def self.warn_if_not_installed
        JobTick.logger.warn(
          "[JobTick] #{SCHEDULE_FILE} found but JobTick::WheneverSetup.install!(self) " \
          "is not installed there; no Whenever monitors registered"
        )
      end
      private_class_method :warn_if_not_installed

      def self.schedule_path
        File.expand_path(SCHEDULE_FILE, JobTick.root)
      end
      private_class_method :schedule_path
    end
  end
end
