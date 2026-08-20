# frozen_string_literal: true

require "spec_helper"
require "socket"

RSpec.describe JobTick::Dispatcher do
  before do
    JobTick.configure do |c|
      c.api_key     = "test-key"
      c.enabled     = true
      c.environment = "production"
      c.queue_limit = 4
    end
    # Override the spec_helper default so we exercise the real async path.
    described_class.synchronous = false
  end

  after do
    described_class.reset!
  end

  describe ".enqueue" do
    it "delivers queued payloads via HTTP on the background thread" do
      stub = stub_request(:post, "https://api.jobtick.app/v1/ping/x.job")
             .with(body: { status: "started" }.to_json)
             .to_return(status: 200)

      described_class.enqueue("/ping/x.job", { status: :started })
      described_class.flush

      expect(stub).to have_been_requested
    end

    it "drops payloads non-blockingly when the queue is saturated" do
      # Block the dispatcher thread on a slow stub so the queue fills up.
      gate = Queue.new
      stub_request(:post, %r{https://api\.jobtick\.app/v1/ping/.*}).to_return do
        gate.pop
        { status: 200 }
      end

      # Trigger thread start with the first enqueue (will block on the stub).
      described_class.enqueue("/ping/slow.job", { status: :started })
      sleep 0.05 # let the worker pick up the first item

      # Queue limit is 4; push more than 4 additional items.
      20.times { |i| described_class.enqueue("/ping/n#{i}", { status: :started }) }

      expect(described_class.dropped).to be > 0

      # Release the worker so cleanup proceeds.
      100.times { gate.push(nil) }
    end

    it "reconnects after a network error" do
      call_count = 0
      stub_request(:post, "https://api.jobtick.app/v1/ping/y.job").to_return do
        call_count += 1
        raise Errno::ECONNRESET if call_count == 1

        { status: 200 }
      end

      described_class.enqueue("/ping/y.job", { status: :started })
      described_class.enqueue("/ping/y.job", { status: :completed })
      described_class.flush

      expect(call_count).to eq(2)
    end
  end

  describe ".send_sync" do
    it "blocks the caller until the request completes" do
      stub = stub_request(:post, "https://api.jobtick.app/v1/monitors/sync")
             .with(body: { monitors: [] }.to_json)
             .to_return(status: 200)

      described_class.send_sync("/monitors/sync", { monitors: [] })

      expect(stub).to have_been_requested
    end
  end

  describe ".shutdown" do
    it "drains in-flight items within the timeout" do
      stub = stub_request(:post, "https://api.jobtick.app/v1/ping/z.job").to_return(status: 200)

      5.times { described_class.enqueue("/ping/z.job", { status: :started }) }
      described_class.shutdown(timeout: 2)

      expect(stub).to have_been_requested.at_least_times(1)
    end

    it "is safe to call when not running" do
      expect { described_class.shutdown }.not_to raise_error
    end
  end

  describe "circuit breaker" do
    it "opens after 3 consecutive failures and stops attempting requests" do
      stub_request(:post, %r{/ping/.*}).to_raise(Errno::ECONNREFUSED)

      3.times { |i| described_class.enqueue("/ping/fail#{i}", { status: :started }) }
      described_class.flush
      described_class.enqueue("/ping/after-open", { status: :started })
      described_class.flush

      expect(WebMock).to have_requested(:post, %r{/ping/(fail\d|after-open)}).times(3)
    end

    it "closes again on the first success after being open" do
      stub_request(:post, %r{/ping/.*}).to_raise(Errno::ECONNREFUSED)
      3.times { |i| described_class.enqueue("/ping/fail#{i}", { status: :started }) }
      described_class.flush

      # Time-travel past the initial backoff window so the circuit is eligible to try again.
      future = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3600
      allow(Process).to receive(:clock_gettime).and_call_original
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(future)

      stub_request(:post, "https://api.jobtick.app/v1/ping/recovered.job").to_return(status: 200)
      described_class.enqueue("/ping/recovered.job", { status: :started })
      described_class.flush

      expect(WebMock).to have_requested(:post, "https://api.jobtick.app/v1/ping/recovered.job").once
    end

    it "opens immediately and warns exactly once on a 401" do
      stub_request(:post, "https://api.jobtick.app/v1/ping/unauth.job").to_return(status: 401)
      logger = instance_double(Logger, warn: nil)
      allow(JobTick).to receive(:logger).and_return(logger)

      2.times do
        described_class.enqueue("/ping/unauth.job", { status: :started })
        described_class.flush
      end

      expect(logger).to have_received(:warn).with(/rejected the API key/).once
      expect(WebMock).to have_requested(:post, "https://api.jobtick.app/v1/ping/unauth.job").once
    end
  end

  describe ".reset!" do
    it "closes a connection opened via .send_sync even though the dispatcher thread never started" do
      stub_request(:post, "https://api.jobtick.app/v1/monitors/sync").to_return(status: 200)
      described_class.send_sync("/monitors/sync", { monitors: [] })

      expect(described_class.instance_variable_get(:@http)).not_to be_nil
      expect(described_class.instance_variable_get(:@running)).to be_falsy

      described_class.reset!

      expect(described_class.instance_variable_get(:@http)).to be_nil
    end
  end

  describe "fork safety", if: Process.respond_to?(:fork) do
    # WebMock never opens a real socket, so this exercises real TCP — the only
    # way to reproduce what the parent's persistent connection looks like to a
    # forked child.
    around do |example|
      WebMock.allow_net_connect!
      example.run
    ensure
      WebMock.disable_net_connect!
    end

    it "builds its own connection and dispatcher thread in a forked child, without touching the parent's" do
      server = TCPServer.new("127.0.0.1", 0)
      received = Queue.new
      server_thread = Thread.new do
        loop do
          conn = server.accept
          Thread.new(conn) do |sock|
            request_line = sock.gets
            received << request_line
            while (line = sock.gets) && line != "\r\n"; end
            sock.write("HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
            sock.close
          end
        end
      rescue IOError
        nil # server closed
      end

      JobTick.configure { |c| c.endpoint = "http://127.0.0.1:#{server.addr[1]}/v1" }
      described_class.send_sync("/monitors/sync", { monitors: [] })
      received.pop
      parent_http = described_class.instance_variable_get(:@http)
      expect(parent_http).not_to be_nil

      read, write = IO.pipe
      pid = fork do
        read.close
        described_class.send_sync("/ping/child", { status: :started })
        child_http = described_class.instance_variable_get(:@http)
        write.puts(child_http.equal?(parent_http) ? "same" : "different")
        write.close
        exit!(0) # skip at_exit hooks / RSpec teardown in the child
      end
      write.close
      result = read.read
      Process.wait(pid)
      read.close

      received.pop # the child's own request

      expect(result.strip).to eq("different")
      expect(described_class.instance_variable_get(:@http)).to equal(parent_http) # parent untouched
    ensure
      server&.close
      server_thread&.kill
    end
  end
end
