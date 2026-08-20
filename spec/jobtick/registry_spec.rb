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
      expect(JobTick.client).to have_received(:register).with([sq_monitor], app_name: nil, sync: true)
    end

    it "passes the Rails app name when Rails is defined" do
      rails_app = double("app", class: double("class", module_parent_name: "MyApp"))
      stub_const("Rails", double("Rails", application: rails_app))

      described_class.sync
      expect(JobTick.client).to have_received(:register).with([sq_monitor], app_name: "MyApp", sync: true)
    end

    it "passes prune: true when configured" do
      JobTick.config.prune = true
      rails_app = double("app", class: double("class", module_parent_name: "MyApp"))
      stub_const("Rails", double("Rails", application: rails_app))

      described_class.sync
      expect(JobTick.client).to have_received(:register).with([sq_monitor], app_name: "MyApp", prune: true, sync: true)
    end

    it "defaults to a blocking (sync: true) register call" do
      described_class.sync
      expect(JobTick.client).to have_received(:register).with(anything, hash_including(sync: true))
    end

    it "passes sync: false through when called with sync: false" do
      described_class.sync(sync: false)
      expect(JobTick.client).to have_received(:register).with(anything, hash_including(sync: false))
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

    it "populates JobTick.monitor_map with a task-to-key lookup" do
      described_class.sync
      expect(JobTick.monitor_map).to eq("CleanupJob" => "solid_queue.cleanup")
    end

    it "includes entries from all parsers in the monitor map" do
      sidekiq_monitor = { key: "sidekiq.hard_worker", schedule: "0 * * * *", source: "sidekiq", task: "HardWorker" }
      allow(JobTick::Parsers::Sidekiq).to receive(:parse).and_return([sidekiq_monitor])

      described_class.sync
      expect(JobTick.monitor_map).to include(
        "CleanupJob" => "solid_queue.cleanup",
        "HardWorker" => "sidekiq.hard_worker"
      )
    end

    it "clears the monitor map when nothing is discovered" do
      JobTick.monitor_map = { "OldJob" => "old.key" }
      allow(JobTick::Parsers::SolidQueue).to receive(:parse).and_return([])

      described_class.sync
      expect(JobTick.monitor_map).to be_empty
    end

    it "keeps the first monitor and warns when two monitors target the same task" do
      duplicate = { key: "solid_queue.cleanup_again", schedule: "every hour", source: "solid_queue",
                    task: "CleanupJob" }
      allow(JobTick::Parsers::SolidQueue).to receive(:parse).and_return([sq_monitor, duplicate])
      logger = instance_double(Logger, warn: nil)
      allow(JobTick).to receive(:logger).and_return(logger)

      described_class.sync

      expect(JobTick.monitor_map).to eq("CleanupJob" => "solid_queue.cleanup")
      expect(logger).to have_received(:warn).with(/solid_queue\.cleanup_again/)
    end
  end
end
