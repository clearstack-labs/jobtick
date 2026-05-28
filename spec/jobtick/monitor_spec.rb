# frozen_string_literal: true

require "spec_helper"

RSpec.describe JobTick::Monitor do
  before do
    JobTick.configure do |c|
      c.api_key     = "test-key"
      c.enabled     = true
      c.environment = "production"
    end
    allow(JobTick.client).to receive(:ping)
  end

  describe ".run" do
    it "sends started and completed pings around a successful block" do
      described_class.run("my.job") { :ok }

      expect(JobTick.client).to have_received(:ping).with("my.job", status: :started)
      expect(JobTick.client).to have_received(:ping).with("my.job", status: :completed, duration: a_kind_of(Float))
    end

    it "returns the block's return value" do
      result = described_class.run("my.job") { 42 }
      expect(result).to eq(42)
    end

    it "sends a failed ping and re-raises on error" do
      expect do
        described_class.run("my.job") { raise "boom" }
      end.to raise_error("boom")

      expect(JobTick.client).to have_received(:ping).with("my.job", status: :failed, message: "boom")
    end

    it "does not send any pings when disabled" do
      JobTick.config.enabled = false
      described_class.run("my.job") { :ok }
      expect(JobTick.client).not_to have_received(:ping)
    end

    it "still yields when disabled" do
      JobTick.config.enabled = false
      result = described_class.run("my.job") { 99 }
      expect(result).to eq(99)
    end

    it "records a positive duration" do
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(0.0, 1.5)

      described_class.run("my.job") { :ok }

      expect(JobTick.client).to have_received(:ping).with("my.job", status: :completed, duration: 1.5)
    end
  end
end
