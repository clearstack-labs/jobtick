# frozen_string_literal: true

module JobTick
  module Parsers
    class Whenever
      SCHEDULE_FILE = "config/schedule.rb"

      def self.parse
        return [] unless defined?(::Whenever)
        return [] unless File.exist?(SCHEDULE_FILE)

        schedule = ::Whenever::JobList.new(file: SCHEDULE_FILE)
        schedule.jobs.flat_map do |period, jobs|
          jobs.map do |job|
            {
              key: job_key(job),
              schedule: period.to_s,
              source: "whenever",
              task: job[:task].to_s.strip
            }
          end
        end
      rescue StandardError => e
        JobTick.logger.warn("[JobTick] Whenever parser failed: #{e.message}")
        []
      end

      def self.job_key(job)
        task = job[:task].to_s.strip
        slug = task.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
        "whenever.#{slug}"
      end
      private_class_method :job_key
    end
  end
end
