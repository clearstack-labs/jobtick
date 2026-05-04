# frozen_string_literal: true

require "spec_helper"

RSpec.describe JobTick::Parsers::Whenever do
  let(:fixture_path) { File.expand_path("../../fixtures/schedule.rb", __dir__) }

  # Build a Whenever::JobList stub whose .new returns a list with specified jobs.
  # Uses a real method definition to sidestep verify_partial_doubles.
  def stub_whenever(jobs_by_period)
    list_instance = double("Whenever::JobList", jobs: jobs_by_period) # rubocop:disable RSpec/VerifiedDoubles
    stub_class = Class.new do
      define_singleton_method(:new) { |**_| list_instance }
    end
    stub_const("Whenever", Module.new)
    stub_const("Whenever::JobList", stub_class)
    stub_const("JobTick::Parsers::Whenever::SCHEDULE_FILE", fixture_path)
  end

  describe ".parse" do
    context "when Whenever is not defined" do
      it "returns an empty array" do
        hide_const("Whenever") if defined?(Whenever)
        expect(described_class.parse).to eq([])
      end
    end

    context "when the schedule file does not exist" do
      it "returns an empty array" do
        stub_const("Whenever", Module.new)
        stub_const("JobTick::Parsers::Whenever::SCHEDULE_FILE", "nonexistent.rb")
        expect(described_class.parse).to eq([])
      end
    end

    context "when Whenever is available" do
      it "returns a job descriptor for each discovered job" do
        stub_whenever(
          "1.hour" => [{ task: "InvoiceJob.perform_later" }],
          "1.day"  => [{ task: "rake reports:daily" }]
        )
        result = described_class.parse
        expect(result.length).to eq(2)
        expect(result.map { |j| j[:source] }.uniq).to eq(["whenever"])
      end

      it "generates a key from the task name" do
        stub_whenever("1.hour" => [{ task: "InvoiceJob.perform_later" }])
        result = described_class.parse
        expect(result.first[:key]).to eq("whenever.invoicejob_perform_later")
      end

      it "captures the schedule period" do
        stub_whenever("1.hour" => [{ task: "SomeJob.run" }])
        result = described_class.parse
        expect(result.first[:schedule]).to eq("1.hour")
      end

      it "captures the task string" do
        stub_whenever("1.hour" => [{ task: "bundle exec rake reports:daily" }])
        result = described_class.parse
        expect(result.first[:task]).to eq("bundle exec rake reports:daily")
      end

      it "returns an empty array and does not raise when the parser fails" do
        stub_whenever("1.hour" => [{ task: "SomeJob.run" }])
        list_double = double("Whenever::JobList") # rubocop:disable RSpec/VerifiedDoubles
        allow(list_double).to receive(:jobs).and_raise(StandardError, "parse error")
        stub_class = Class.new { define_singleton_method(:new) { |**_| list_double } }
        stub_const("Whenever::JobList", stub_class)

        expect { described_class.parse }.not_to raise_error
        expect(described_class.parse).to eq([])
      end
    end
  end
end
