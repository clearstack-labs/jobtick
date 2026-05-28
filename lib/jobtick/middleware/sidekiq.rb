# frozen_string_literal: true

module JobTick
  module Middleware
    class Sidekiq
      def call(_worker, job, _queue, &)
        # Active Job wrappers are handled by the around_perform hook
        return yield if job["wrapped"]

        key = JobTick.monitor_map[job["class"]]
        return yield unless key

        JobTick::Monitor.run(key, &)
      end

      def self.install
        ::Sidekiq.configure_server do |config|
          config.server_middleware do |chain|
            chain.add(JobTick::Middleware::Sidekiq)
          end
        end
      end
    end
  end
end
