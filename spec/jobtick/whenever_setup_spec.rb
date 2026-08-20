# frozen_string_literal: true

require "spec_helper"
require "whenever"
require "jobtick/whenever_setup"
require "open3"
require "tmpdir"
require "fileutils"

RSpec.describe JobTick::WheneverSetup do
  let(:endpoint) { "https://api.jobtick.app/v1" }

  before do
    JobTick.configure do |c|
      c.api_key = "test-key"
      c.endpoint = endpoint
    end
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

    it "includes the configured endpoint in each template" do
      templates = capture_templates(schedule)
      templates.each_value { |tmpl| expect(tmpl).to include(endpoint) }
    end

    it "includes started, completed, and failed ping paths in each template" do
      templates = capture_templates(schedule)

      %i[runner rake command].each do |type|
        expect(templates[type]).to include("$JOBTICK_KEY/started"),   "#{type} missing started ping"
        expect(templates[type]).to include("$JOBTICK_KEY/completed"), "#{type} missing completed ping"
        expect(templates[type]).to include("$JOBTICK_KEY/failed"),    "#{type} missing failed ping"
      end
    end

    it "uses if/then/else so a failed completed-ping cannot masquerade as a failed job" do
      # Regression check for the pre-0.3.0 bug: `inner && completed || failed` fires the
      # `failed` ping whenever the *completed* curl call itself fails — even though the
      # job succeeded — because shell `&&`/`||` chains, unlike if/then/else, don't stop
      # once one branch has already run.
      templates = capture_templates(schedule)
      templates.each_value do |tmpl|
        expect(tmpl).to match(/if .* then .* else .* fi ; exit \$rc\z/), tmpl
      end
    end

    it "bounds each curl call so a hung request can't wedge a cron slot" do
      templates = capture_templates(schedule)
      templates.each_value { |tmpl| expect(tmpl.scan("--max-time 10").length).to eq(3) }
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

    it "injects the monitor key as a job option rather than recomputing it in shell" do
      templates = capture_templates(schedule)
      templates.each_value { |tmpl| expect(tmpl).to include("JOBTICK_KEY=:jobtick_key") }
    end
  end

  describe "end-to-end, against a real Whenever::JobList" do
    let(:fixture_path) { File.expand_path("../fixtures/schedule.rb", __dir__) }

    it "resolves :jobtick_key to the same key Parsers::Whenever reads back out" do
      output = Whenever::JobList.new(file: fixture_path).generate_cron_output

      expect(output).to include("JOBTICK_KEY=whenever.invoicejob_perform_later")
      expect(output).to include("JOBTICK_KEY=whenever.reports_daily")
      expect(output).to include("JOBTICK_KEY=whenever.weeklydigestjob_perform_later")
    end

    it "produces a runnable if/then/else command with the real inner task substituted" do
      output = Whenever::JobList.new(file: fixture_path).generate_cron_output

      expect(output).to include("bundle exec rails runner")
      expect(output).to include("InvoiceJob.perform_later")
      expect(output).to match(
        /if cd .* then rc=0 ; curl .*completed.* ; else rc=\$\? ; curl .*failed.* ; fi ; exit \$rc/
      )
    end
  end

  describe "shell precedence, under a real sh" do
    # Regression test for the pre-0.3.0 bug: run the actual generated shell
    # fragment under `sh`, with a fake `curl` that fails specifically on the
    # *completed* ping, and prove a successful job cannot emit a `failed`
    # ping — the false alert this rewrite exists to prevent.
    around do |example|
      Dir.mktmpdir do |dir|
        @bin_dir = dir
        @marker  = File.join(dir, "failed_ping_sent")
        write_fake_curl(dir, @marker)
        example.run
      end
    end

    def write_fake_curl(dir, marker)
      path = File.join(dir, "curl")
      File.write(path, <<~SH)
        #!/bin/sh
        url="$*"
        case "$url" in
          *:*/started) exit 0 ;;
          *:*/completed) exit 1 ;;   # simulate a transient failure on this ping specifically
          *:*/failed) touch "#{marker}" ; exit 0 ;;
        esac
      SH
      FileUtils.chmod("+x", path)
    end

    def run_wrapped(inner_cmd)
      script = described_class.send(:wrap, "http://127.0.0.1:0", inner_cmd).sub(":jobtick_key", "test.job")
      env = { "PATH" => "#{@bin_dir}:#{ENV.fetch("PATH", nil)}" }
      _out, status = Open3.capture2e(env, "sh", "-c", script)
      status
    end

    it "does not send a failed ping when the job succeeds but the completed-ping curl fails" do
      status = run_wrapped("true")

      expect(File.exist?(@marker)).to be(false)
      expect(status.exitstatus).to eq(0) # the job's own success, via `exit $rc`, must still come through
    end

    it "still sends a failed ping, and preserves the exit code, when the job itself fails" do
      status = run_wrapped("false")

      expect(File.exist?(@marker)).to be(true)
      expect(status.exitstatus).to eq(1)
    end
  end
end
