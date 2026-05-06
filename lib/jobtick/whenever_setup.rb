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
  # any per-job configuration.
  module WheneverSetup
    def self.install!(schedule)
      endpoint = JobTick.config.endpoint

      schedule.job_type :runner,  wrap(endpoint, "cd :path && bundle exec rails runner ':task' :output")
      schedule.job_type :rake,    wrap(endpoint, "cd :path && bundle exec rake :task :output")
      schedule.job_type :command, wrap(endpoint, "cd :path && :task :output")
    end

    def self.wrap(endpoint, inner_cmd)
      # Shell equivalent of Parsers.slugify: downcase, collapse non-alnum runs to _, strip leading/trailing _.
      sed = "sed 's/[^a-z0-9][^a-z0-9]*/_/g' | sed 's/^_*//;s/_*$//'"
      slug = "$(printf '%s' ':task' | tr '[:upper:]' '[:lower:]' | #{sed})"
      key_assign = %(JOBTICK_KEY="whenever.#{slug}")

      "#{key_assign} ; " \
        "curl -sf \"#{endpoint}/ping/$JOBTICK_KEY/started\" ; " \
        "#{inner_cmd} && " \
        "curl -sf \"#{endpoint}/ping/$JOBTICK_KEY/completed\" || " \
        "curl -sf \"#{endpoint}/ping/$JOBTICK_KEY/failed\""
    end
    private_class_method :wrap
  end
end
