# frozen_string_literal: true

module JobTick
  class Configuration
    DEFAULT_QUEUE_LIMIT = 1000

    attr_accessor :api_key, :endpoint, :environment, :enabled, :prune, :queue_limit,
                  :sync_on_boot, :ping_started

    def initialize
      @endpoint     = "https://api.jobtick.app/v1"
      @environment  = ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "production"
      @enabled      = @environment == "production"
      @prune        = false
      @queue_limit  = DEFAULT_QUEUE_LIMIT
      @sync_on_boot = true
      @ping_started = true
    end

    def enabled?
      @enabled && !@api_key.nil?
    end
  end
end
