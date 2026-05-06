# frozen_string_literal: true

require "spec_helper"

RSpec.describe JobTick::Hooks::ActiveJob do
  # Minimal stub that replicates the ActiveJob::Base around_perform API
  let(:fake_base) do
    Class.new do
      def self.around_perform_blocks
        @around_perform_blocks ||= []
      end

      def self.around_perform(&block)
        around_perform_blocks << block
      end
    end
  end

  before do
    JobTick.configure do |c|
      c.api_key  = "test-key"
      c.enabled  = true
    end
    allow(JobTick.client).to receive(:ping)
    JobTick.monitor_map = { "CleanupJob" => "solid_queue.cleanup" }
    fake_base.include(described_class)
  end

  def execute_job(job_name, &work)
    work ||= -> {}
    job = double("job", class: double("class", name: job_name))
    fake_base.around_perform_blocks.last.call(job, work)
  end

  it "sends started and completed pings for a known job" do
    execute_job("CleanupJob")

    expect(JobTick.client).to have_received(:ping).with("solid_queue.cleanup", status: :started)
    expect(JobTick.client).to have_received(:ping).with("solid_queue.cleanup", status: :completed,
                                                                               duration: a_kind_of(Float))
  end

  it "yields to the job body" do
    performed = false
    execute_job("CleanupJob") { performed = true }
    expect(performed).to be true
  end

  it "sends a failed ping and re-raises on error" do
    expect { execute_job("CleanupJob") { raise "boom" } }.to raise_error("boom")

    expect(JobTick.client).to have_received(:ping).with("solid_queue.cleanup", status: :failed, message: "boom")
  end

  it "passes through without pinging for an unknown job" do
    execute_job("SomeOtherJob")
    expect(JobTick.client).not_to have_received(:ping)
  end

  it "still yields for an unknown job" do
    performed = false
    execute_job("SomeOtherJob") { performed = true }
    expect(performed).to be true
  end

  it "does not ping when disabled" do
    JobTick.config.enabled = false
    execute_job("CleanupJob")
    expect(JobTick.client).not_to have_received(:ping)
  end

  it "registers exactly one around_perform callback" do
    expect(fake_base.around_perform_blocks.size).to eq(1)
  end
end
