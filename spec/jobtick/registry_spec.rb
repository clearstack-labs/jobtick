# frozen_string_literal: true

require "spec_helper"

RSpec.describe JobTick::Registry do
  before do
    JobTick.configure do |c|
      c.api_key     = "test-key"
      c.enabled     = true
      c.environment = "production"
    end
    allow(JobTick.client).to receive(:register)
  end

  describe ".sync" do
    let(:sq_monitor) do
      { key: "solid_queue.cleanup", schedule: "every day", source: "solid_queue", task: "CleanupJob" }
    end

    before do
      allow(JobTick::Parsers::Whenever).to receive(:parse).and_return([])
      allow(JobTick::Parsers::SolidQueue).to receive(:parse).and_return([sq_monitor])
      allow(JobTick::Parsers::Sidekiq).to receive(:parse).and_return([])
    end

    it "aggregates results from all parsers" do
      monitors = described_class.sync
      expect(monitors).to eq([sq_monitor])
    end

    it "calls client.register with the discovered monitors" do
      described_class.sync
      expect(JobTick.client).to have_received(:register).with([sq_monitor])
    end

    it "returns an empty array and skips register when nothing is discovered" do
      allow(JobTick::Parsers::SolidQueue).to receive(:parse).and_return([])
      result = described_class.sync
      expect(result).to eq([])
      expect(JobTick.client).not_to have_received(:register)
    end

    it "flattens results from multiple parsers" do
      wh_monitor = { key: "whenever.foo", schedule: "1h", source: "whenever", task: "foo" }
      allow(JobTick::Parsers::Whenever).to receive(:parse).and_return([wh_monitor])

      monitors = described_class.sync
      expect(monitors).to contain_exactly(wh_monitor, sq_monitor)
    end
  end
end
