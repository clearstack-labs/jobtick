## [0.1.3] - 2026-05-05

- Add `JobTick::WheneverSetup.install!(self)` — one-line setup that overrides Whenever's built-in `runner`, `rake`, and `command` job types to send heartbeat pings automatically, with no per-job changes required
- Extract shared `Parsers.slugify` helper, remove redundant `.to_s` calls, unify guard style

## [0.1.2] - 2026-04-30

- Add automatic ping instrumentation for Solid Queue (via `ActiveJob::Base` `around_perform` hook) and Sidekiq (via server middleware)

## [0.1.1] - 2026-04-28

- Send `app_name` on monitor sync

## [0.1.0] - 2026-04-27

- Initial release
