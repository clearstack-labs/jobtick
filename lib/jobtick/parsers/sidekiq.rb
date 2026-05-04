# frozen_string_literal: true

module JobTick
  module Parsers
    class Sidekiq
      def self.parse
        return [] unless defined?(::Sidekiq)

        if defined?(::Sidekiq::Cron::Job)
          return ::Sidekiq::Cron::Job.all.map do |job|
            {
              key:      "sidekiq.#{slugify(job.name)}",
              schedule: job.cron,
              source:   "sidekiq",
              task:     job.klass
            }
          end
        end

        if defined?(::Sidekiq::Periodic::LoopSet)
          periodic = sidekiq_periodic_config
          return (periodic || []).map do |klass, opts|
            {
              key:      "sidekiq.#{slugify(klass.to_s)}",
              schedule: opts[:cron] || opts[:every].to_s,
              source:   "sidekiq",
              task:     klass.to_s
            }
          end
        end

        []
      rescue StandardError => e
        JobTick.logger.warn("[JobTick] Sidekiq parser failed: #{e.message}")
        []
      end

      def self.slugify(str)
        str.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
      end
      private_class_method :slugify

      def self.sidekiq_periodic_config
        # Sidekiq 7+ uses default_configuration; older uses options
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
