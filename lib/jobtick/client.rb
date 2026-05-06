# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module JobTick
  class Client
    TIMEOUT = 5

    def ping(monitor_key, status:, duration: nil, message: nil)
      return unless JobTick.config.enabled
      return if JobTick.config.api_key.nil?

      payload = { status: status }
      payload[:duration] = duration.round(3) if duration
      payload[:message]  = message           if message

      post("/ping/#{monitor_key}", payload)
    end

    def register(monitors, app_name: nil)
      return unless JobTick.config.enabled
      return if JobTick.config.api_key.nil?

      payload = { monitors: monitors }
      payload[:app_name] = app_name if app_name.present?
      post("/monitors/sync", payload)
    end

    private

    def post(path, body)
      uri  = URI("#{JobTick.config.endpoint}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = uri.scheme == "https"
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"]  = "application/json"
      request["Authorization"] = "Bearer #{JobTick.config.api_key}"
      request["User-Agent"]    = "jobtick-ruby/#{JobTick::VERSION}"
      request.body             = body.to_json

      http.request(request)
    rescue StandardError => e
      JobTick.logger.warn("[JobTick] HTTP request failed (#{path}): #{e.message}")
      nil
    end
  end
end
