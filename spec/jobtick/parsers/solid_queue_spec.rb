# frozen_string_literal: true

require "spec_helper"

RSpec.describe JobTick::Parsers::SolidQueue do
  let(:fixture_path)     { File.expand_path("../../fixtures/recurring.yml", __dir__) }
  let(:env_scoped_path)  { File.expand_path("../../fixtures/recurring_env_scoped.yml", __dir__) }

  before do
    JobTick.configure { |c| c.environment = "production" }
  end

  describe ".parse" do
    context "when the file does not exist" do
      before { stub_const("JobTick::Parsers::SolidQueue::RECURRING_FILE", "nonexistent.yml") }

      it "returns an empty array" do
        expect(described_class.parse).to eq([])
      end
    end

    context "with a flat recurring.yml" do
      before { stub_const("JobTick::Parsers::SolidQueue::RECURRING_FILE", fixture_path) }

      it "returns one descriptor per job" do
        result = described_class.parse
        expect(result.length).to eq(3)
      end

      it "namespaces keys with solid_queue prefix" do
        result = described_class.parse
        expect(result.map { |j| j[:key] }).to all(start_with("solid_queue."))
      end

      it "maps class names to task" do
        result = described_class.parse
        tasks  = result.map { |j| j[:task] }
        expect(tasks).to include("CleanupJob", "DigestEmailJob", "NightlyReportJob")
      end

      it "sets source to solid_queue" do
        result = described_class.parse
        expect(result.map { |j| j[:source] }.uniq).to eq(["solid_queue"])
      end

      it "captures the schedule string" do
        result  = described_class.parse
        cleanup = result.find { |j| j[:key] == "solid_queue.periodic_cleanup" }
        expect(cleanup[:schedule]).to eq("every day at 9am")
      end
    end

    context "with an environment-scoped recurring.yml" do
      before do
        stub_const("JobTick::Parsers::SolidQueue::RECURRING_FILE", env_scoped_path)
        JobTick.configure { |c| c.environment = "production" }
      end

      it "returns only jobs for the current environment" do
        result = described_class.parse
        expect(result.length).to eq(1)
        expect(result.first[:task]).to eq("CleanupJob")
      end

      it "returns staging jobs when environment is staging" do
        JobTick.configure { |c| c.environment = "staging" }
        result = described_class.parse
        expect(result.length).to eq(1)
        expect(result.first[:task]).to eq("StagingJob")
      end

      it "returns an empty array, not the environment names themselves, when the " \
         "current environment has no entry" do
        JobTick.configure { |c| c.environment = "test" }
        logger = instance_double(Logger, warn: nil)
        allow(JobTick).to receive(:logger).and_return(logger)

        result = described_class.parse

        expect(result).to eq([])
        expect(logger).to have_received(:warn).with(/no entry for "test"/)
      end
    end

    context "with a recurring.yml mixing class: and command: tasks" do
      let(:command_only_path) { File.expand_path("../../fixtures/recurring_command_only.yml", __dir__) }

      before { stub_const("JobTick::Parsers::SolidQueue::RECURRING_FILE", command_only_path) }

      it "registers only the class-based task" do
        result = described_class.parse
        expect(result.length).to eq(1)
        expect(result.first[:task]).to eq("CleanupJob")
      end

      it "logs a warning naming the skipped command-based task" do
        logger = instance_double(Logger, warn: nil)
        allow(JobTick).to receive(:logger).and_return(logger)

        described_class.parse

        expect(logger).to have_received(:warn).with(/shell_backup/)
      end
    end

    context "with a malformed YAML file" do
      before do
        allow(YAML).to receive(:load_file).and_raise(Psych::SyntaxError.new("file", 1, 1, 0, "bad yaml", "context"))
        stub_const("JobTick::Parsers::SolidQueue::RECURRING_FILE", fixture_path)
      end

      it "returns an empty array without raising" do
        expect { described_class.parse }.not_to raise_error
        expect(described_class.parse).to eq([])
      end
    end
  end
end
