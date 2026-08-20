# frozen_string_literal: true

require "spec_helper"
require "whenever"

# These specs build a real Whenever::JobList and read its real
# generate_cron_output — deliberately not a hand-rolled stub of
# Whenever::JobList's API. Whenever::JobList has no public `jobs` reader
# (only attr_reader :roles) and its internal @jobs is a private, nested
# structure with no [] accessor on Job either — a prior version of this spec
# stubbed a `jobs` API that Whenever doesn't actually expose, and the
# resulting Parsers::Whenever raised NoMethodError against every real app,
# silently swallowed into []. Testing against the real gem is what catches
# that class of failure.
RSpec.describe JobTick::Parsers::Whenever do
  let(:fixture_path) { File.expand_path("../../fixtures/schedule.rb", __dir__) }
  let(:not_installed_path) { File.expand_path("../../fixtures/schedule_not_installed.rb", __dir__) }

  before do
    JobTick.configure do |c|
      c.api_key  = "test-key"
      c.endpoint = "https://api.jobtick.app/v1"
    end
  end

  describe ".parse" do
    context "when the whenever gem is not available" do
      it "returns an empty array" do
        allow(described_class).to receive(:whenever_available?).and_return(false)
        expect(described_class.parse).to eq([])
      end
    end

    context "when the schedule file does not exist" do
      it "returns an empty array" do
        stub_const("JobTick::Parsers::Whenever::SCHEDULE_FILE", "nonexistent.rb")
        expect(described_class.parse).to eq([])
      end
    end

    context "when config/schedule.rb has JobTick::WheneverSetup.install!(self)" do
      before { stub_const("JobTick::Parsers::Whenever::SCHEDULE_FILE", fixture_path) }

      it "returns one monitor descriptor per scheduled job" do
        result = described_class.parse
        expect(result.length).to eq(3)
        expect(result.map { |j| j[:source] }.uniq).to eq(["whenever"])
      end

      it "recovers the exact key WheneverSetup injected into the job" do
        result = described_class.parse
        expect(result.map { |j| j[:key] }).to contain_exactly(
          "whenever.invoicejob_perform_later",
          "whenever.reports_daily",
          "whenever.weeklydigestjob_perform_later"
        )
      end

      it "captures the real cron expression, not the DSL frequency string" do
        result = described_class.parse
        by_key = result.to_h { |m| [m[:key], m[:schedule]] }

        expect(by_key["whenever.invoicejob_perform_later"]).to eq("0 * * * *")
        expect(by_key["whenever.reports_daily"]).to eq("0 0 * * *")
        expect(by_key["whenever.weeklydigestjob_perform_later"]).to eq("0 9 * * 1")
      end

      it "leaves task nil — Whenever jobs are pinged by curl, never by a Ruby hook" do
        result = described_class.parse
        expect(result.map { |j| j[:task] }.uniq).to eq([nil])
      end
    end

    context "when config/schedule.rb exists but WheneverSetup was never installed" do
      before { stub_const("JobTick::Parsers::Whenever::SCHEDULE_FILE", not_installed_path) }

      it "returns an empty array" do
        expect(described_class.parse).to eq([])
      end

      it "logs an actionable warning instead of failing silently" do
        logger = instance_double(Logger, warn: nil)
        allow(JobTick).to receive(:logger).and_return(logger)

        described_class.parse

        expect(logger).to have_received(:warn).with(/WheneverSetup\.install!/)
      end
    end

    context "when building the job list raises" do
      before { stub_const("JobTick::Parsers::Whenever::SCHEDULE_FILE", fixture_path) }

      it "returns an empty array and does not raise" do
        allow(Whenever::JobList).to receive(:new).and_raise(StandardError, "parse error")

        expect { described_class.parse }.not_to raise_error
        expect(described_class.parse).to eq([])
      end
    end
  end
end
