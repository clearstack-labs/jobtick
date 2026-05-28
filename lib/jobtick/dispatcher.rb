# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "openssl"

module JobTick
  # Asynchronous, single-threaded HTTP dispatcher with a persistent keep-alive
  # connection. Job threads call .enqueue and return immediately; the dispatcher
  # daemon thread drains the queue and posts to the JobTick API.
  #
  # All HTTP work (sync register + async pings) shares one Net::HTTP instance
  # serialized by @http_mutex. The connection is reopened lazily after errors.
  module Dispatcher
    SHUTDOWN_SIGNAL = :__shutdown__
    HEADER_CONTENT_TYPE = "application/json"
    USER_AGENT = "jobtick-ruby/#{JobTick::VERSION}".freeze
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 5
    KEEP_ALIVE_TIMEOUT = 30

    NETWORK_ERRORS = [
      IOError, EOFError,
      Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::ECONNABORTED,
      Errno::EPIPE, Errno::ETIMEDOUT, Errno::EHOSTUNREACH,
      Net::OpenTimeout, Net::ReadTimeout,
      OpenSSL::SSL::SSLError, SocketError
    ].freeze

    class << self
      attr_accessor :synchronous

      def enqueue(path, payload)
        return send_request(path, payload) if @synchronous

        ensure_started
        @queue.push([path, payload], true)
        nil
      rescue ThreadError
        @dropped += 1
        nil
      end

      def send_sync(path, payload)
        send_request(path, payload)
      end

      def flush(timeout: 5)
        return unless @running && @queue

        deadline = monotonic + timeout
        until @queue.empty? && @inflight.zero?
          sleep 0.001
          break if monotonic > deadline
        end
      end

      def shutdown(timeout: 2)
        return unless @running

        @running = false
        @queue&.push(SHUTDOWN_SIGNAL)
        @thread&.join(timeout)
        close_http
        nil
      end

      def dropped
        @dropped || 0
      end

      def reset!
        shutdown(timeout: 1) if @running
        @queue = nil
        @thread = nil
        @dropped = 0
        @inflight = 0
        @endpoint_uri = nil
        @at_exit_registered = false
        @synchronous = false
      end

      private

      def ensure_started
        return if @running

        boot_mutex.synchronize do
          return if @running

          @queue   = SizedQueue.new(queue_limit)
          @dropped = 0
          @inflight = 0
          @thread = Thread.new { run_loop }
          @thread.name = "jobtick-dispatcher" if @thread.respond_to?(:name=)
          @running = true
          register_at_exit
        end
      end

      def boot_mutex
        @boot_mutex ||= Mutex.new
      end

      def http_mutex
        @http_mutex ||= Mutex.new
      end

      def queue_limit
        JobTick.config.queue_limit || Configuration::DEFAULT_QUEUE_LIMIT
      end

      def register_at_exit
        return if @at_exit_registered

        @at_exit_registered = true
        at_exit { shutdown }
      end

      def run_loop
        while (item = @queue.pop)
          break if item == SHUTDOWN_SIGNAL

          @inflight = 1
          path, payload = item
          send_request(path, payload)
          @inflight = 0
        end
      rescue StandardError => e
        JobTick.logger.warn("[JobTick] Dispatcher thread crashed: #{e.message}")
      ensure
        close_http
      end

      def send_request(path, payload)
        body = JSON.generate(payload)
        full_path = "#{endpoint_uri.path}#{path}"
        http_mutex.synchronize do
          http = http_connection
          request = Net::HTTP::Post.new(full_path)
          request["Content-Type"]  = HEADER_CONTENT_TYPE
          request["Authorization"] = "Bearer #{JobTick.config.api_key}"
          request["User-Agent"]    = USER_AGENT
          request.body = body
          http.request(request)
        end
      rescue *NETWORK_ERRORS => e
        JobTick.logger.warn("[JobTick] HTTP request failed (#{path}): #{e.message}")
        teardown_http
        nil
      rescue StandardError => e
        JobTick.logger.warn("[JobTick] HTTP request failed (#{path}): #{e.message}")
        nil
      end

      def endpoint_uri
        @endpoint_uri ||= URI(JobTick.config.endpoint)
      end

      def http_connection
        return @http if @http&.started?

        uri = endpoint_uri
        @http = Net::HTTP.new(uri.host, uri.port)
        @http.use_ssl            = uri.scheme == "https"
        @http.open_timeout       = OPEN_TIMEOUT
        @http.read_timeout       = READ_TIMEOUT
        @http.keep_alive_timeout = KEEP_ALIVE_TIMEOUT
        @http.start
        @http
      end

      def teardown_http
        return unless @http

        @http.finish if @http.started?
      rescue StandardError
        nil
      ensure
        @http = nil
      end

      def close_http
        http_mutex.synchronize { teardown_http }
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
