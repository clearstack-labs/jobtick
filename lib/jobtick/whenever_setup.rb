# frozen_string_literal: true

require "jobtick"

module JobTick
  # Overrides Whenever's built-in job types to wrap execution with jobtick pings.
  #
  # Usage — add one line to config/schedule.rb:
  #
  #   JobTick::WheneverSetup.install!(self)
  #
  # This replaces the :runner, :rake, and :command job types so that every
  # scheduled job automatically sends started/completed/failed heartbeats without
  # any per-job configuration. The monitor key is injected as a literal job
  # option (:jobtick_key) rather than recomputed in shell, so it always matches
  # the key Parsers::Whenever reads back out of the generated crontab.
  module WheneverSetup
    TEMPLATES = {
      runner: "cd :path && bundle exec rails runner ':task' :output",
      rake: "cd :path && bundle exec rake :task :output",
      command: ":task :output"
    }.freeze

    KEY_INJECTOR = Module.new do
      TEMPLATES.each_key do |type|
        define_method(type) do |task, *args|
          opts = args[0].is_a?(Hash) ? args[0].dup : {}
          opts[:jobtick_key] = JobTick::Parsers.whenever_key(task)
          super(task, opts)
        end
      end
    end
    private_constant :KEY_INJECTOR

    def self.install!(schedule)
      endpoint = JobTick.config.endpoint

      TEMPLATES.each { |type, inner| schedule.job_type(type, wrap(endpoint, inner)) }

      # Prepended after job_type defines the singleton methods above, but order
      # doesn't matter for resolution: a prepended module always sits ahead of
      # the singleton class in the ancestor chain, so this always wins and
      # `super` always reaches the method job_type just defined.
      schedule.singleton_class.prepend(KEY_INJECTOR)
    end

    def self.wrap(endpoint, inner_cmd)
      key_assign = "JOBTICK_KEY=:jobtick_key"
      started   = %(curl -sf --max-time 10 "#{endpoint}/ping/$JOBTICK_KEY/started")
      completed = %(curl -sf --max-time 10 "#{endpoint}/ping/$JOBTICK_KEY/completed")
      failed    = %(curl -sf --max-time 10 "#{endpoint}/ping/$JOBTICK_KEY/failed")

      "#{key_assign} ; #{started} ; " \
        "if #{inner_cmd} ; then rc=0 ; #{completed} ; " \
        "else rc=$? ; #{failed} ; fi ; exit $rc"
    end
    private_class_method :wrap
  end
end
