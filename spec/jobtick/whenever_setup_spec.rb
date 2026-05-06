# frozen_string_literal: true

require "spec_helper"
require "jobtick/whenever_setup"

RSpec.describe JobTick::WheneverSetup do
  let(:endpoint) { "https://api.jobtick.app/v1" }

  before do
    JobTick.configure { |c| c.api_key = "test-key" }
  end

  def capture_templates(schedule)
    templates = {}
    allow(schedule).to receive(:job_type) { |type, tmpl| templates[type] = tmpl }
    described_class.install!(schedule)
    templates
  end

  describe ".install!" do
    let(:schedule) { double("Whenever::JobList") }

    it "overrides runner, rake, and command job types" do
      expect(schedule).to receive(:job_type).with(:runner, anything)
      expect(schedule).to receive(:job_type).with(:rake, anything)
      expect(schedule).to receive(:job_type).with(:command, anything)
      described_class.install!(schedule)
    end

    it "includes the configured endpoint in the runner template" do
      templates = capture_templates(schedule)
      expect(templates[:runner]).to include(endpoint)
    end

    it "includes started, completed, and failed ping paths in each template" do
      templates = capture_templates(schedule)

      %i[runner rake command].each do |type|
        expect(templates[type]).to include("$JOBTICK_KEY/started"),   "#{type} missing started ping"
        expect(templates[type]).to include("$JOBTICK_KEY/completed"), "#{type} missing completed ping"
        expect(templates[type]).to include("$JOBTICK_KEY/failed"),    "#{type} missing failed ping"
      end
    end

    it "derives the monitor key from :task using the whenever. prefix" do
      templates = capture_templates(schedule)
      expect(templates[:runner]).to include('JOBTICK_KEY="whenever.')
    end

    it "uses the shell slugify expression referencing :task" do
      templates = capture_templates(schedule)
      expect(templates[:runner]).to include("printf '%s' ':task'")
      expect(templates[:runner]).to include("tr '[:upper:]' '[:lower:]'")
    end

    it "places the started ping before the inner command" do
      templates = capture_templates(schedule)
      started_pos = templates[:runner].index("started")
      runner_pos  = templates[:runner].index("rails runner")
      expect(started_pos).to be < runner_pos
    end

    it "wraps rake tasks with bundle exec rake" do
      templates = capture_templates(schedule)
      expect(templates[:rake]).to include("bundle exec rake :task")
    end

    it "wraps runner tasks with bundle exec rails runner" do
      templates = capture_templates(schedule)
      expect(templates[:runner]).to include("bundle exec rails runner ':task'")
    end
  end
end
