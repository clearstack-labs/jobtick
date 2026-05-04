# frozen_string_literal: true

module JobTick
  class Monitor
    def self.run(key)
      return yield unless JobTick.config.enabled

      started_at = Time.now
      JobTick.client.ping(key, status: :started)
      result   = yield
      duration = Time.now - started_at
      JobTick.client.ping(key, status: :completed, duration: duration)
      result
    rescue StandardError => e
      JobTick.client.ping(key, status: :failed, message: e.message)
      raise
    end
  end
end
