# frozen_string_literal: true

namespace :jobtick do
  desc "Sync discovered jobs with jobtick.app"
  task sync: :environment do
    monitors = JobTick::Registry.sync
    count    = monitors&.length || 0
    puts "[JobTick] Synced #{count} monitor(s)"
  end

  namespace :whenever do
    desc "Print Whenever job_type wrappers to add to config/schedule.rb for heartbeat injection"
    task :setup do
      endpoint = JobTick.config.endpoint
      puts <<~RUBY
        # Add to config/schedule.rb to enable JobTick heartbeat injection for Whenever jobs:

        job_type :jobtick_runner, %(curl -sf "#{endpoint}/ping/:monitor_key/started" ; ) \\
                                  %(bundle exec rails runner ':task' :output && ) \\
                                  %(curl -sf "#{endpoint}/ping/:monitor_key/completed" || ) \\
                                  %(curl -sf "#{endpoint}/ping/:monitor_key/failed")

        job_type :jobtick_rake,   %(curl -sf "#{endpoint}/ping/:monitor_key/started" ; ) \\
                                  %(bundle exec rake :task :output && ) \\
                                  %(curl -sf "#{endpoint}/ping/:monitor_key/completed" || ) \\
                                  %(curl -sf "#{endpoint}/ping/:monitor_key/failed")

        # Then use jobtick_runner / jobtick_rake instead of runner / rake, e.g.:
        # every 1.hour do
        #   jobtick_runner "InvoiceJob.perform_later", monitor_key: "invoice_job"
        # end
      RUBY
    end
  end
end
