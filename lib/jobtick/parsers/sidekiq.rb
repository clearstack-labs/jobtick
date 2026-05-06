# frozen_string_literal: true

module JobTick
  module Parsers
    def self.slugify(str)
      str.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
    end

    class Sidekiq
      def self.parse
        return [] unless defined?(::Sidekiq)
        return parse_cron_jobs if defined?(::Sidekiq::Cron::Job)
        return parse_periodic_jobs if defined?(::Sidekiq::Periodic::LoopSet)

        []
      rescue StandardError => e
        JobTick.logger.warn("[JobTick] Sidekiq parser failed: #{e.message}")
        []
      end

      def self.parse_cron_jobs
        ::Sidekiq::Cron::Job.all.map do |job|
          { key: "sidekiq.#{Parsers.slugify(job.name)}", schedule: job.cron, source: "sidekiq", task: job.klass }
        end
      end
      private_class_method :parse_cron_jobs

      def self.parse_periodic_jobs
        periodic = sidekiq_periodic_config
        (periodic || []).map do |klass, opts|
          { key: "sidekiq.#{Parsers.slugify(klass.to_s)}", schedule: opts[:cron] || opts[:every].to_s,
            source: "sidekiq", task: klass.to_s }
        end
      end
      private_class_method :parse_periodic_jobs

      def self.sidekiq_periodic_config
        if ::Sidekiq.respond_to?(:default_configuration)
          ::Sidekiq.default_configuration[:periodic]
        else
          ::Sidekiq.options[:periodic]
        end
      end
      private_class_method :sidekiq_periodic_config
    end
  end
end
