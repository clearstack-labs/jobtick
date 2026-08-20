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
  #
  # Fork safety: .enqueue and .send_sync are always called from the thread
  # that survives a fork (the caller's thread — a job thread, or the process
  # that just booted). Neither the background dispatcher thread nor its
  # Net::HTTP socket survive a fork, even though the Ruby objects referencing
  # them do (they're just inherited memory). guard_fork! runs first on both
  # public entry points and drops those stale references — without closing
  # the socket, which still belongs to the parent — so each process lazily
  # builds its own connection and dispatcher thread.
  module Dispatcher
    SHUTDOWN_SIGNAL = :__shutdown__
    FLUSH_SENTINEL = :__flush__
    HEADER_CONTENT_TYPE = "application/json"
    USER_AGENT = "jobtick-ruby/#{JobTick::VERSION}".freeze
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 5
    KEEP_ALIVE_TIMEOUT = 30

    UNAUTHORIZED_CODES = %w[401 403].freeze
    FAILURE_THRESHOLD = 3
    CIRCUIT_INITIAL_BACKOFF = 30
    CIRCUIT_MAX_BACKOFF = 300
    STATUS_WARN_INTERVAL = 60

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

        guard_fork!
        ensure_started
        @queue.push([path, payload], true)
        nil
      rescue ThreadError
        dropped_mutex.synchronize { @dropped = (@dropped || 0) + 1 }
        nil
      end

      def send_sync(path, payload)
        guard_fork!
        send_request(path, payload)
      end

      def flush(timeout: 5)
        return unless @running && @queue && @thread&.alive?

        ack = Queue.new
        begin
          @queue.push([FLUSH_SENTINEL, ack])
        rescue ThreadError
          return
        end
        ack.pop(timeout: timeout)
        nil
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
        close_http # shutdown is a no-op if only .send_sync ever ran, so close explicitly too
        @queue = nil
        @thread = nil
        @dropped = 0
        @endpoint_uri = nil
        @at_exit_registered = false
        @synchronous = false
        @pid = nil
        @consecutive_failures = 0
        @circuit_until = nil
        @unauthorized_warned = false
        @status_warned_at = nil
      end

      private

      # Atomic under fork_mutex so a thread that loses the race can never null
      # out @queue/@http *after* another thread has already rebuilt them for
      # the new pid — once this returns, @pid always matches Process.pid, and
      # that transition only ever happens once per fork.
      def guard_fork!
        return if @pid == Process.pid

        fork_mutex.synchronize do
          return if @pid == Process.pid

          http_mutex.synchronize { @http = nil } # not #finish — the socket belongs to the parent
          boot_mutex.synchronize do
            @queue = nil
            @thread = nil
            @running = false
          end
          @pid = Process.pid
        end
      end

      def fork_mutex
        @fork_mutex ||= Mutex.new
      end

      def ensure_started
        return if @running

        boot_mutex.synchronize do
          return if @running

          @queue   = SizedQueue.new(queue_limit)
          @dropped = 0
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

      def dropped_mutex
        @dropped_mutex ||= Mutex.new
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

          key, payload = item
          if key.equal?(FLUSH_SENTINEL)
            payload.push(true)
            next
          end

          send_request(key, payload)
        end
      rescue StandardError => e
        JobTick.logger.warn("[JobTick] Dispatcher thread crashed: #{e.message}")
      ensure
        close_http
      end

      def send_request(path, payload)
        return nil if circuit_open?

        response = http_mutex.synchronize { http_connection.request(build_request(path, payload)) }
        handle_response(path, response)
        response
      rescue *NETWORK_ERRORS => e
        JobTick.logger.warn("[JobTick] HTTP request failed (#{path}): #{e.message}")
        teardown_http
        record_failure
        nil
      rescue StandardError => e
        JobTick.logger.warn("[JobTick] HTTP request failed (#{path}): #{e.message}")
        nil
      end

      def build_request(path, payload)
        request = Net::HTTP::Post.new("#{endpoint_uri.path}#{path}")
        request["Content-Type"]  = HEADER_CONTENT_TYPE
        request["Authorization"] = "Bearer #{JobTick.config.api_key}"
        request["User-Agent"]    = USER_AGENT
        request.body = JSON.generate(payload)
        request
      end

      def handle_response(path, response)
        code = response.code

        if code.start_with?("2")
          record_success
        elsif UNAUTHORIZED_CODES.include?(code)
          warn_unauthorized_once
          open_circuit(CIRCUIT_MAX_BACKOFF)
        else
          record_failure
          warn_status_throttled(code, path)
        end
      end

      def circuit_open?
        !@circuit_until.nil? && monotonic < @circuit_until
      end

      def open_circuit(seconds)
        @circuit_until = monotonic + seconds + rand(5)
      end

      def record_failure
        @consecutive_failures = (@consecutive_failures || 0) + 1
        return if @consecutive_failures < FAILURE_THRESHOLD

        backoff = CIRCUIT_INITIAL_BACKOFF * (2**(@consecutive_failures - FAILURE_THRESHOLD))
        open_circuit([backoff, CIRCUIT_MAX_BACKOFF].min)
      end

      def record_success
        @consecutive_failures = 0
        @circuit_until = nil
      end

      def warn_unauthorized_once
        return if @unauthorized_warned

        @unauthorized_warned = true
        JobTick.logger.warn("[JobTick] API rejected the API key (401/403); pings are being discarded")
      end

      def warn_status_throttled(code, path)
        @status_warned_at ||= {}
        last = @status_warned_at[code]
        now = monotonic
        return if last && (now - last) < STATUS_WARN_INTERVAL

        @status_warned_at[code] = now
        JobTick.logger.warn("[JobTick] API returned #{code} (#{path})")
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
