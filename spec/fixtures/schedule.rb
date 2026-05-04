# Whenever schedule fixture — used by spec/jobtick/parsers/whenever_spec.rb

every 1.hour do
  runner "InvoiceJob.perform_later"
end

every :day do
  rake "reports:daily"
end

every "0 9 * * 1" do
  runner "WeeklyDigestJob.perform_later"
end
