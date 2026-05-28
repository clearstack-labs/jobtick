# frozen_string_literal: true

require "spec_helper"

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
end
