# frozen_string_literal: true

require_relative "dispatcher"

module JobTick
  class Client
    PING_PREFIX = "/ping/"
    SYNC_PATH   = "/monitors/sync"

    def ping(monitor_key, status:, duration: nil, message: nil)
      return unless JobTick.config.enabled?

      payload = { status: status }
      payload[:duration] = duration.round(3) if duration
      payload[:message]  = message           if message

      Dispatcher.enqueue("#{PING_PREFIX}#{monitor_key}", payload)
    end

    def register(monitors, app_name: nil, prune: false, sync: true)
      return unless JobTick.config.enabled?

      payload = { monitors: monitors }
      payload[:app_name] = app_name if app_name && !app_name.empty?
      payload[:prune]    = true if prune

      if sync
        Dispatcher.send_sync(SYNC_PATH, payload)
      else
        Dispatcher.enqueue(SYNC_PATH, payload)
      end
    end
  end
end
