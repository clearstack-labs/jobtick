# frozen_string_literal: true

require "spec_helper"

RSpec.describe JobTick::Middleware::Sidekiq do
  let(:middleware) { described_class.new }
  let(:worker)     { double("worker") }

  before do
    JobTick.configure do |c|
      c.api_key  = "test-key"
      c.enabled  = true
    end
    allow(JobTick.client).to receive(:ping)
    JobTick.monitor_map = { "HardWorker" => "sidekiq.hard_worker" }
  end

  def call(job, &block)
    block ||= -> {}
    middleware.call(worker, job, "default", &block)
  end

  it "sends started and completed pings for a known worker" do
    call("class" => "HardWorker")

    expect(JobTick.client).to have_received(:ping).with("sidekiq.hard_worker", status: :started)
    expect(JobTick.client).to have_received(:ping).with("sidekiq.hard_worker", status: :completed, duration: a_kind_of(Float))
  end

  it "yields to the job body" do
    performed = false
    call("class" => "HardWorker") { performed = true }
    expect(performed).to be true
  end

  it "sends a failed ping and re-raises on error" do
    expect { call("class" => "HardWorker") { raise "oops" } }.to raise_error("oops")

    expect(JobTick.client).to have_received(:ping).with("sidekiq.hard_worker", status: :failed, message: "oops")
  end

  it "passes through without pinging for an unknown worker" do
    call("class" => "UnknownWorker")
    expect(JobTick.client).not_to have_received(:ping)
  end

  it "still yields for an unknown worker" do
    performed = false
    call("class" => "UnknownWorker") { performed = true }
    expect(performed).to be true
  end

  it "skips pinging for Active Job wrappers (around_perform hook handles those)" do
    call("class" => "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper", "wrapped" => "HardWorker")
    expect(JobTick.client).not_to have_received(:ping)
  end

  it "still yields for Active Job wrappers" do
    performed = false
    call("class" => "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper", "wrapped" => "HardWorker") { performed = true }
    expect(performed).to be true
  end

  it "does not ping when disabled" do
    JobTick.config.enabled = false
    call("class" => "HardWorker")
    expect(JobTick.client).not_to have_received(:ping)
  end
end
