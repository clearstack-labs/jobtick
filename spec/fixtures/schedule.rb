# frozen_string_literal: true

# Whenever schedule fixture — used by spec/jobtick/parsers/whenever_spec.rb
# and spec/jobtick/whenever_setup_spec.rb. Loaded via Whenever::JobList, so it
# runs against the real `whenever` gem rather than a hand-rolled stub of its
# internal API — that's precisely the gap that let the pre-0.3.0 parser ship
# broken (it never worked against the real Whenever::JobList).

set :output, nil

require "jobtick/whenever_setup"
JobTick::WheneverSetup.install!(self)

every 1.hour do
  runner "InvoiceJob.perform_later"
end

every :day do
  rake "reports:daily"
end

every "0 9 * * 1" do
  runner "WeeklyDigestJob.perform_later"
end
