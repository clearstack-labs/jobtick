# frozen_string_literal: true

module JobTick
  module Parsers
    SLUG_RE = /[^a-z0-9]+/
    SLUG_TRIM_RE = /\A_+|_+\z/

    def self.slugify(str)
      str.downcase.gsub(SLUG_RE, "_").gsub(SLUG_TRIM_RE, "")
    end

    # Shared by Parsers::Whenever (which reads it back out of the generated
    # crontab) and WheneverSetup (which injects it as a job option). Keeping
    # both sides derived from this one method is what guarantees the key a
    # monitor is registered under matches the key its pings are sent to.
    def self.whenever_key(task)
      "whenever.#{slugify(task.to_s.strip)}"
    end
  end
end
