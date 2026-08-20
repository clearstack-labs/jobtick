# frozen_string_literal: true

# Fixture for spec/jobtick/parsers/whenever_spec.rb: a schedule.rb that never
# calls JobTick::WheneverSetup.install!(self), so no job carries a
# JOBTICK_KEY= — exercises the "found the file but it's not wired up" path.

set :output, nil

every 1.hour do
  runner "InvoiceJob.perform_later"
end
