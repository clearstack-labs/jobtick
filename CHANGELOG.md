## [0.3.0] - 2026-08-20

- **Fix: Whenever monitors never actually registered.** `Parsers::Whenever` called a `Whenever::JobList#jobs` API that doesn't exist on the real gem (only `attr_reader :roles`), so every discovery attempt raised and was silently swallowed — no Whenever job has ever been registered by prior versions. The parser now reads the real, public `generate_cron_output` instead, and `WheneverSetup` injects the monitor key as a literal job option so the registered key and the pinged key are always the same value by construction. `config/schedule.rb` needs `require 'jobtick/whenever_setup'` before `JobTick::WheneverSetup.install!(self)` now — see the README.
- **Fix: the Whenever shell wrapper could send a false failure alert.** `inner && ping_completed || ping_failed` fired the `failed` ping whenever the *completed* ping's own `curl` call failed — even though the job succeeded. Rewritten as `if <job> ; then ... completed ; else ... failed ; fi`, plus `curl --max-time 10` so a hung ping can't wedge a cron slot, and `exit $rc` so cron still sees the job's real exit status.
- **Fix: the persistent HTTPS connection was fork-unsafe.** A clustered app server (Puma with `preload_app!`, Passenger, Unicorn) forking after boot left every worker sharing one file descriptor, corrupting or dropping pings under load. The dispatcher now detects a pid change on every call from `.enqueue`/`.send_sync` and rebuilds its connection and background thread in the child without touching the parent's socket.
- **Fix: `Configuration#environment`-scoped `config/recurring.yml` registered environment names as monitors.** When the current environment had no matching top-level key, the parser fell back to treating the whole file as a task list — registering `solid_queue.production`, `solid_queue.staging`, etc. as permanently-down monitors. It now returns no monitors (with a warning) instead.
- **Fix:** HTTP responses were previously discarded entirely — a bad API key returned 401 forever in total silence. The dispatcher now logs a 401/403 once and opens a circuit breaker so pings stop being sent to an API that's rejecting them; other error statuses are logged at a throttled rate.
- **Fix:** `Dispatcher.reset!` could leave a stale connection open (e.g. after only `.send_sync` had ever run), so a subsequent endpoint change kept posting to the old host.
- Add a circuit breaker: after 3 consecutive network failures, the dispatcher stops attempting connections for a backed-off window (30s–300s) instead of paying a connect timeout per queued ping during an outage.
- Boot-time sync no longer blocks: it now goes through the async dispatcher, and is skipped entirely for `rails console`, `rails runner`, and rake tasks (configurable via `config.sync_on_boot`). `rake jobtick:sync` remains a blocking call for use as an explicit deploy step.
- Add `config.ping_started` (default `true`) to suppress the `started` ping for high-frequency jobs.
- `Parsers::Whenever`/`Parsers::SolidQueue` now resolve their config file paths against `Rails.root` (or `Dir.pwd` outside Rails) instead of the process's current working directory.
- Two monitors that resolve to the same job class now log a warning naming both, instead of one silently losing its pings to the other.
- `Configuration#enabled?` is now used consistently by `Client` and `Monitor` instead of each open-coding the same check.

## [0.2.0] - 2026-05-28

- Performance: pings are now dispatched asynchronously on a single daemon thread, so job workers no longer block on network I/O. A persistent, keep-alive HTTPS connection is reused for all pings (no more TCP/TLS handshake per ping).
- Performance: switch to `Process.clock_gettime(CLOCK_MONOTONIC)` for duration measurement — no `Time` object allocation per job, and immune to wall-clock jumps.
- Performance: lazy-load parsers, hooks, middleware, and the registry — only Rails boots that have JobTick enabled pay for them.
- Performance: the monitor map is frozen after sync, and parser allocations are trimmed on the boot path.
- Add `Configuration#queue_limit` (default 1000) to bound the background ping queue; over-limit pings are dropped non-blockingly rather than back-pressuring the job thread.

### Measured impact

Benchmarked with `spec/benchmarks/monitor_bench.rb` (10,000 iterations, WebMock-stubbed endpoint so the numbers reflect gem-internal overhead, not real network latency):

| Metric (per monitored job) | v0.1.4 | v0.2.0 | Change |
|---|---:|---:|---:|
| Job-thread blocking time | 400.6 µs | 2.0 µs | **~200× faster** |
| Object allocations on job thread | 2,390 | 9 | **~265× fewer** |
| End-to-end CPU time (incl. background dispatch) | 400.6 µs | 18.1 µs | **~22× less CPU** |

In production, where each ping pays real network RTT, the job-thread speedup is significantly larger: a single 20 ms RTT × 2–3 pings per job is ~50 ms blocking under v0.1.4, versus ~2 µs under v0.2.0 (~25,000× on the worker thread). Run `bundle exec ruby spec/benchmarks/monitor_bench.rb [iterations]` to reproduce.

## [0.1.4] - 2026-05-05

- Add `prune` configuration option — when enabled, monitors absent from the latest sync payload are permanently deleted, keeping the dashboard in sync with your schedule config
- Remove stale `.gem` build artifact from repository

## [0.1.3] - 2026-05-05

- Add `JobTick::WheneverSetup.install!(self)` — one-line setup that overrides Whenever's built-in `runner`, `rake`, and `command` job types to send heartbeat pings automatically, with no per-job changes required
- Extract shared `Parsers.slugify` helper, remove redundant `.to_s` calls, unify guard style

## [0.1.2] - 2026-04-30

- Add automatic ping instrumentation for Solid Queue (via `ActiveJob::Base` `around_perform` hook) and Sidekiq (via server middleware)

## [0.1.1] - 2026-04-28

- Send `app_name` on monitor sync

## [0.1.0] - 2026-04-27

- Initial release
