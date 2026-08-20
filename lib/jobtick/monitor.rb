# frozen_string_literal: true

module JobTick
  class Monitor
    MONOTONIC = Process::CLOCK_MONOTONIC

    def self.run(key)
      config = JobTick.config
      return yield unless config.enabled?

      client = JobTick.client
      client.ping(key, status: :started) if config.ping_started
      started = Process.clock_gettime(MONOTONIC)
      result  = yield
      duration = Process.clock_gettime(MONOTONIC) - started
      client.ping(key, status: :completed, duration: duration)
      result
    rescue StandardError => e
      JobTick.client.ping(key, status: :failed, message: e.message)
      raise
    end
  end
end
