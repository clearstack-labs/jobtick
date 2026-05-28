# frozen_string_literal: true

# Compares per-monitored-job overhead of:
#   BASELINE: a faithful reproduction of the v0.1.4 hot path (sync Net::HTTP per
#             ping, Time.now × 2, no connection reuse).
#   CURRENT:  the v0.2.0 async dispatcher (queue push from the job thread).
#
# Run with:
#   bundle exec ruby spec/benchmarks/monitor_bench.rb [iterations]
#
# WebMock intercepts both code paths so we are measuring gem-internal overhead,
# not real network latency. (Real-world wins are *larger* than what this
# benchmark shows because the baseline numbers do not include actual RTT.)

$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))

require "benchmark"
require "json"
require "net/http"
require "uri"
require "webmock"
include WebMock::API
WebMock.enable!
WebMock.disable_net_connect!

require "jobtick"

ITERATIONS = (ARGV[0] || 10_000).to_i
ENDPOINT   = "https://api.jobtick.app/v1"

JobTick.configure do |c|
  c.api_key     = "bench-key"
  c.endpoint    = ENDPOINT
  c.enabled     = true
  c.environment = "production"
end

stub_request(:post, %r{https://api\.jobtick\.app/v1/.*}).to_return(status: 200, body: "")

# --- Baseline (v0.1.4 reproduction) ----------------------------------------

module Baseline
  TIMEOUT = 5

  class Client
    def ping(monitor_key, status:, duration: nil, message: nil)
      payload = { status: status }
      payload[:duration] = duration.round(3) if duration
      payload[:message]  = message           if message
      post("/ping/#{monitor_key}", payload)
    end

    private

    def post(path, body)
      uri  = URI("#{ENDPOINT}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = uri.scheme == "https"
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"]  = "application/json"
      request["Authorization"] = "Bearer #{JobTick.config.api_key}"
      request["User-Agent"]    = "jobtick-ruby/baseline"
      request.body             = body.to_json
      http.request(request)
    rescue StandardError
      nil
    end
  end

  CLIENT = Client.new

  def self.run(key)
    started = Time.now
    CLIENT.ping(key, status: :started)
    result   = yield
    duration = Time.now - started
    CLIENT.ping(key, status: :completed, duration: duration)
    result
  rescue StandardError => e
    CLIENT.ping(key, status: :failed, message: e.message)
    raise
  end
end

# --- Current (v0.2.0 async dispatcher) -------------------------------------

JobTick::Dispatcher.synchronous = false

# --- Allocation deltas (steady state, single iteration) --------------------

def alloc_delta(repeat: 1000)
  GC.start
  GC.disable
  before = GC.stat[:total_allocated_objects]
  repeat.times { yield }
  after = GC.stat[:total_allocated_objects]
  GC.enable
  (after - before).to_f / repeat
end

puts "ITERATIONS = #{ITERATIONS}"
puts

# Warm both paths once so JIT/loaders don't skew the first run.
Baseline.run("warm") { :ok }
JobTick::Monitor.run("warm") { :ok }
JobTick::Dispatcher.flush

# --- Wall clock ------------------------------------------------------------

job_body = -> { 1 + 1 } # near-zero job to isolate gem overhead

baseline_time = Benchmark.realtime do
  ITERATIONS.times { Baseline.run("bench.job", &job_body) }
end

current_time = Benchmark.realtime do
  ITERATIONS.times { JobTick::Monitor.run("bench.job", &job_body) }
end
# Wait for background drainage so we're comparing apples to apples for total work.
flush_time = Benchmark.realtime { JobTick::Dispatcher.flush(timeout: 30) }

puts "WALL CLOCK"
puts "  Baseline (sync, no keep-alive):   #{format('%.3f', baseline_time)} s total, " \
     "#{format('%.2f', baseline_time / ITERATIONS * 1_000_000)} µs/job"
puts "  Current (async dispatcher):       #{format('%.3f', current_time)} s total, " \
     "#{format('%.2f', current_time / ITERATIONS * 1_000_000)} µs/job (job-thread blocking time)"
puts "  Current + background drain:       #{format('%.3f', current_time + flush_time)} s total, " \
     "#{format('%.2f', (current_time + flush_time) / ITERATIONS * 1_000_000)} µs/job (incl. dispatcher work)"
puts "  Speedup (job-thread blocking):    #{format('%.1fx', baseline_time / current_time)}"
puts

# --- Per-job allocations (averaged over 1000 iterations) -------------------

baseline_allocs = alloc_delta { Baseline.run("alloc.job", &job_body) }
current_allocs  = alloc_delta { JobTick::Monitor.run("alloc.job", &job_body) }
JobTick::Dispatcher.flush

puts "TOTAL ALLOCATIONS PER JOB (mean of 1000 iterations, job thread only)"
puts format("  Baseline:  %7.1f objects/job", baseline_allocs)
puts format("  Current:   %7.1f objects/job", current_allocs)
puts format("  Reduction: %7.1f objects/job (%.1fx fewer)",
            baseline_allocs - current_allocs, baseline_allocs / current_allocs)

JobTick::Dispatcher.shutdown
