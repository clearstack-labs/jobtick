# JobTick

[![Gem Version](https://badge.fury.io/rb/jobtick.svg)](https://rubygems.org/gems/jobtick)
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

### Environments

**JobTick is only active in production by default.** In `development`, `staging`, or any other environment it silently does nothing — no pings are sent, no monitors are registered, no errors are raised. This means you can deploy the gem and configure it without worrying about local runs polluting your monitors or counting toward your plan.

If you want to enable JobTick in a non-production environment (e.g. to test your setup on staging before going live), opt in explicitly:

```ruby
# config/initializers/jobtick.rb

# Enable on staging only
JobTick.configure do |config|
  config.api_key  = ENV['JOBTICK_API_KEY']
  config.enabled  = Rails.env.production? || Rails.env.staging?
end
```

```ruby
# Enable everywhere — useful for a quick local smoke-test
JobTick.configure do |config|
  config.api_key  = ENV['JOBTICK_API_KEY']
  config.enabled  = true
end
```

```ruby
# Drive it from an env var so you can toggle without a deploy
JobTick.configure do |config|
  config.api_key  = ENV['JOBTICK_API_KEY']
  config.enabled  = ENV['JOBTICK_ENABLED'] == 'true'
end
```

### Removing stale monitors automatically

By default, monitors are only added — nothing is removed when you delete a job from your schedule. To have each deploy also clean up monitors that are no longer in your config, enable pruning:

```ruby
JobTick.configure do |config|
  config.api_key = ENV['JOBTICK_API_KEY']
  config.prune   = true   # remove monitors absent from the latest sync
end
```

With `prune` enabled, a deploy acts as the single source of truth: any monitor whose key is not present in the current payload is permanently deleted. You can also remove individual monitors manually from the JobTick dashboard at any time.

### Deploying

JobTick syncs your monitors automatically the first time a web or worker process boots after a deploy — this sync runs in the background and never blocks startup, even if the JobTick API is slow or unreachable.

To skip the wait until that first boot (or to sync from CI as an explicit deploy step), run it directly:

```
bundle exec rake jobtick:sync
```

This is the one case where the sync blocks — it prints the number of monitors registered, so its output is only trustworthy if it actually waited for the API to respond.

Boot-time sync is automatically skipped for `rails console`, `rails runner`, and any rake task — none of them should pay for a sync just to boot, and `rails runner` matters especially, since Whenever's cron wrapper shells out through it on every tick. Set `config.sync_on_boot = false` to disable the automatic sync everywhere and rely solely on `rake jobtick:sync`.

---

## What gets monitored

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

At boot, JobTick reads this file and registers a monitor for each entry. It then installs an `around_perform` hook into `ActiveJob::Base` so every job execution automatically sends `started`, `completed`, and `failed` pings. No changes to your job files.

Entries scheduled with `command:` instead of `class:` run a raw shell command rather than a Ruby job class, so there's no hook point for JobTick to instrument automatically — these are skipped (with a log line naming them) rather than registered as a monitor JobTick can never ping.

### Sidekiq periodic jobs

Supports both **sidekiq-cron** and **Sidekiq::Periodic**:

```ruby
# sidekiq-cron — loaded from config/sidekiq_cron.yml or in an initializer
Sidekiq::Cron::Job.create(name: 'Nightly Cleanup', cron: '0 2 * * *', class: 'NightlyCleanupWorker')

# Sidekiq::Periodic
Sidekiq.configure_server do |config|
  config.periodic do |mgr|
    mgr.register('0 * * * *', HourlyDigestWorker)
    mgr.register('0 2 * * *', NightlyCleanupWorker)
  end
end
```

JobTick installs a server middleware that wraps every job execution. For native Sidekiq workers (`Sidekiq::Worker` subclasses) pings are sent by the middleware. For Active Job workers dispatched through Sidekiq, pings are sent by the `around_perform` hook instead, so nothing is double-counted.

### Whenever (`config/schedule.rb`)

Whenever schedules jobs as cron shell commands, so there is no Ruby hook point to instrument automatically. Add two lines to the top of `config/schedule.rb`:

```ruby
require 'jobtick/whenever_setup'
JobTick::WheneverSetup.install!(self)
```

`jobtick/whenever_setup` is a separate file from the main gem on purpose — `config/schedule.rb` is evaluated standalone (by `whenever --update-crontab`, and again by JobTick itself at boot to discover your jobs), not as part of a normal Rails boot, so it needs its own explicit require regardless of whether `gem 'jobtick'` is already in your Gemfile.

This overrides the built-in `runner`, `rake`, and `command` job types to wrap every execution with `curl` pings, gated by a real `if`/`then`/`else` so a network blip on the ping itself can never be mistaken for the job failing. Your existing schedule entries need no other changes:

```ruby
require 'jobtick/whenever_setup'
JobTick::WheneverSetup.install!(self)

every 1.day, at: '2:00 am' do
  runner 'InvoiceJob.perform_later'
end

every :hour do
  rake 'reports:sync'
end
```

After adding these lines, run `whenever --update-crontab` as normal and all jobs will start sending heartbeats. JobTick discovers Whenever monitors by reading the same file back with the real `whenever` gem, so `whenever` must be a dependency of your app (it usually already is) — add it with `require: false` is fine, JobTick loads it itself when needed.

---

## What you get

**Silent failure detection** — alerts when a job stops running entirely, not just when it raises an exception. The failure mode your error monitor misses.

**Auto-sync on deploy** — add a job to your schedule, it appears in your dashboard at next deploy. Enable `config.prune = true` to automatically retire monitors when jobs are removed from your schedule.

**Run history** — see every execution: start time, duration, exit status. Spot when a job starts getting slower before it becomes a problem.

**Maintenance windows** — deploying at 3am? Snooze any monitor for a set period so you don't get paged for expected downtime.

**Team alerts** — email and Slack notifications. On-call rotation support on higher plans.

---

## Requirements

- Ruby >= 3.3
- Rails >= 7.0
- One or more of:

| Adapter | Supported versions |
|---|---|
| Solid Queue | >= 0.1 |
| Sidekiq | >= 6 |
| sidekiq-cron | >= 1.0 |
| Whenever | >= 0.10 |

---

---

## License

MIT. See [LICENSE](LICENSE).

---

*Built by [Clearstack Labs](https://clearstacklabs.com)*