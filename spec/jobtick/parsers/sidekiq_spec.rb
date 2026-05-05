# frozen_string_literal: true

require "spec_helper"

RSpec.describe JobTick::Parsers::Sidekiq do
  describe ".parse" do
    context "when Sidekiq is not defined" do
      it "returns an empty array" do
        hide_const("Sidekiq") if defined?(Sidekiq)
        expect(described_class.parse).to eq([])
      end
    end

    context "with sidekiq-cron" do
      # Build stub doubles without verify — Whenever::Cron::Job is a stub class
      let(:fake_job) do
        double("Sidekiq::Cron::Job",
               name: "Invoice Processor",
               cron: "0 * * * *",
               klass: "InvoiceProcessorJob")
      end

      let(:stub_cron_class) do
        Class.new do
          def self.all = []
        end
      end

      before do
        stub_const("Sidekiq", Module.new)
        stub_const("Sidekiq::Cron", Module.new)
        stub_const("Sidekiq::Cron::Job", stub_cron_class)
      end

      it "returns one descriptor per cron job" do
        allow(Sidekiq::Cron::Job).to receive(:all).and_return([fake_job])
        expect(described_class.parse.length).to eq(1)
      end

      it "namespaces the key with sidekiq prefix" do
        allow(Sidekiq::Cron::Job).to receive(:all).and_return([fake_job])
        expect(described_class.parse.first[:key]).to start_with("sidekiq.")
      end

      it "slugifies the job name into the key" do
        allow(Sidekiq::Cron::Job).to receive(:all).and_return([fake_job])
        expect(described_class.parse.first[:key]).to eq("sidekiq.invoice_processor")
      end

      it "captures the cron expression" do
        allow(Sidekiq::Cron::Job).to receive(:all).and_return([fake_job])
        expect(described_class.parse.first[:schedule]).to eq("0 * * * *")
      end

      it "sets the task to the worker class name" do
        allow(Sidekiq::Cron::Job).to receive(:all).and_return([fake_job])
        expect(described_class.parse.first[:task]).to eq("InvoiceProcessorJob")
      end

      it "sets source to sidekiq" do
        allow(Sidekiq::Cron::Job).to receive(:all).and_return([fake_job])
        expect(described_class.parse.first[:source]).to eq("sidekiq")
      end

      it "returns all jobs when multiple are present" do
        jobs = [
          double("job1", name: "job one", cron: "0 1 * * *", klass: "JobOne"),
          double("job2", name: "job two", cron: "0 2 * * *", klass: "JobTwo")
        ]
        allow(Sidekiq::Cron::Job).to receive(:all).and_return(jobs)
        expect(described_class.parse.length).to eq(2)
      end

      it "returns an empty array without raising when a parser error occurs" do
        allow(Sidekiq::Cron::Job).to receive(:all).and_raise(StandardError, "oops")
        expect { described_class.parse }.not_to raise_error
        expect(described_class.parse).to eq([])
      end
    end
  end
end
