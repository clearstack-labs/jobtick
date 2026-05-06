# frozen_string_literal: true

module JobTick
  module Hooks
    module ActiveJob
      def self.included(base)
        base.around_perform do |job, block|
          key = JobTick.monitor_key_for(job.class.name)
          if key
            JobTick::Monitor.run(key) { block.call }
          else
            block.call
          end
        end
      end
    end
  end
end
