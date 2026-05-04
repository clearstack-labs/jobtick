# frozen_string_literal: true

require "spec_helper"

RSpec.describe JobTick::Client do
  subject(:client) { described_class.new }

  before do
    JobTick.configure do |c|
      c.api_key     = "test-key"
      c.endpoint    = "https://api.jobtick.app/v1"
      c.enabled     = true
      c.environment = "production"
    end
  end

  describe "#ping" do
    it "posts a started ping with the correct payload" do
      stub = stub_request(:post, "https://api.jobtick.app/v1/ping/my.job")
               .with(
                 body:    { status: "started" }.to_json,
                 headers: {
                   "Content-Type"  => "application/json",
                   "Authorization" => "Bearer test-key"
                 }
               )
               .to_return(status: 200)

      client.ping("my.job", status: :started)

      expect(stub).to have_been_requested
    end

    it "includes duration when provided" do
      stub = stub_request(:post, "https://api.jobtick.app/v1/ping/my.job")
               .with(body: hash_including("duration" => 1.234))
               .to_return(status: 200)

      client.ping("my.job", status: :completed, duration: 1.2341)

      expect(stub).to have_been_requested
    end

    it "includes message when provided" do
      stub = stub_request(:post, "https://api.jobtick.app/v1/ping/my.job")
               .with(body: hash_including("message" => "something broke"))
               .to_return(status: 200)

      client.ping("my.job", status: :failed, message: "something broke")

      expect(stub).to have_been_requested
    end

    it "does nothing when disabled" do
      JobTick.config.enabled = false
      client.ping("my.job", status: :started)
      expect(a_request(:any, //)).not_to have_been_made
    end

    it "does nothing when api_key is nil" do
      JobTick.config.api_key = nil
      client.ping("my.job", status: :started)
      expect(a_request(:any, //)).not_to have_been_made
    end

    it "returns nil and does not raise on network failure" do
      stub_request(:post, "https://api.jobtick.app/v1/ping/my.job")
        .to_raise(Errno::ECONNREFUSED)

      expect { client.ping("my.job", status: :started) }.not_to raise_error
    end

    it "returns nil and does not raise on timeout" do
      stub_request(:post, "https://api.jobtick.app/v1/ping/my.job")
        .to_timeout

      expect { client.ping("my.job", status: :started) }.not_to raise_error
    end
  end

  describe "#register" do
    let(:monitors) do
      [{ key: "solid_queue.cleanup", schedule: "every day", source: "solid_queue", task: "CleanupJob" }]
    end

    it "posts to /monitors/sync" do
      stub = stub_request(:post, "https://api.jobtick.app/v1/monitors/sync")
               .with(body: { monitors: monitors }.to_json)
               .to_return(status: 200)

      client.register(monitors)

      expect(stub).to have_been_requested
    end

    it "does nothing when disabled" do
      JobTick.config.enabled = false
      client.register(monitors)
      expect(a_request(:any, //)).not_to have_been_made
    end

    it "does not raise on failure" do
      stub_request(:post, "https://api.jobtick.app/v1/monitors/sync").to_raise(SocketError)
      expect { client.register(monitors) }.not_to raise_error
    end
  end
end
