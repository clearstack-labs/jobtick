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
