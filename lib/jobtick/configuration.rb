# frozen_string_literal: true

module JobTick
  class Configuration
    attr_accessor :api_key, :endpoint, :environment, :enabled, :prune

    def initialize
      @endpoint    = "https://api.jobtick.app/v1"
      @environment = ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "production"
      @enabled     = @environment == "production"
      @prune       = false
    end
  end
end
