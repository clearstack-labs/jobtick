# frozen_string_literal: true

module JobTick
  module Hooks
    module ActiveJob
      def self.included(base)
        base.around_perform do |job, block|
          key = JobTick.monitor_map[job.class.name]
          next block.call unless key

          JobTick::Monitor.run(key) { block.call }
        end
      end
    end
  end
end
