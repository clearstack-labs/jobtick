# JobTick

[![Ruby](https://github.com/clearstack-labs/jobtick/actions/workflows/main.yml/badge.svg?branch=main)](https://github.com/clearstack-labs/jobtick/actions/workflows/main.yml)

**Rails job monitoring for Whenever, Solid Queue, and Sidekiq.**
Know when your scheduled jobs stop running — before your users do.

---

## The problem

Your error monitor catches exceptions. Mission Control shows you failed jobs.
Neither tells you when a recurring job **simply stops running**.

No exception. No alert. Nothing.

The Solid Queue scheduler process dies at 2am. Your nightly invoice job hasn't run in three days. Your users notice before you do.

JobTick solves this. It watches every scheduled job in your Rails app and alerts you the moment one goes silent — even when no error is raised.

---

## Why JobTick over Healthchecks.io or Cronitor?

Those tools work — but they require you to manually add a heartbeat ping to every job. Touch 15 job files. Name each monitor by hand. Keep names in sync when jobs are renamed or removed.

JobTick reads your existing config files and registers everything automatically.

```
config/schedule.rb      → Whenever jobs, auto-discovered
config/recurring.yml    → Solid Queue recurring tasks, auto-discovered
sidekiq.yml             → Sidekiq periodic jobs, auto-discovered
```

Add the gem. Add your API key. Deploy. Done.

---

## Installation

Add to your Gemfile:

```ruby
gem 'jobtick'
```

Create an initializer:

```ruby
# config/initializers/jobtick.rb
JobTick.configure do |config|
  config.api_key = ENV['JOBTICK_API_KEY']
end
```

That's it. On next deploy, JobTick reads your schedule config, registers a monitor for every job, and starts tracking.

No changes to individual job files. No manual monitor creation. No names to keep in sync.

---

## What gets monitored

### Whenever (`config/schedule.rb`)

```ruby
# Your existing schedule.rb — no changes needed
every 1.day, at: '2:00 am' do
  runner 'InvoiceJob.perform_later'
end

every :hour do
  runner 'SyncInventoryJob.perform_later'
end
```

JobTick reads this file at deploy time and creates a monitor for each job automatically.

### Solid Queue (`config/recurring.yml`)

```yaml
# Your existing recurring.yml — no changes needed
nightly_report:
  class: NightlyReportJob
  schedule: every day at 3am

sync_exchange_rates:
  class: ExchangeRateJob
  schedule: every hour
```

Each entry becomes a monitor. If `NightlyReportJob` doesn't run within its expected window, you get an alert.

### Sidekiq periodic jobs

```ruby
# Your existing Sidekiq config — no changes needed
Sidekiq.configure_server do |config|
  config.periodic do |mgr|
    mgr.register('0 * * * *', HourlyDigestWorker)
    mgr.register('0 2 * * *', NightlyCleanupWorker)
  end
end
```

---

## What you get

**Silent failure detection** — alerts when a job stops running entirely, not just when it raises an exception. The failure mode your error monitor misses.

**Auto-sync on deploy** — add a job to your schedule, it appears in your dashboard at next deploy. Remove a job, its monitor is automatically retired.

**Run history** — see every execution: start time, duration, exit status. Spot when a job starts getting slower before it becomes a problem.

**Maintenance windows** — deploying at 3am? Snooze any monitor for a set period so you don't get paged for expected downtime.

**Team alerts** — email and Slack notifications. On-call rotation support on higher plans.

---

## Requirements

- Ruby >= 3.2
- Rails >= 7.0
- One or more of: Whenever, Solid Queue, Sidekiq

---

## Status

> **JobTick is currently in development.**
> Sign up for early access at [jobtick.app](https://jobtick.app).
> Launching June 2026.

If you want to follow along or give early feedback, open an issue or watch the repo.

---

## License

MIT. See [LICENSE](LICENSE).

---

*Built by [Clearstack Labs](https://clearstacklabs.com)*