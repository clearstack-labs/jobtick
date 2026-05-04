# frozen_string_literal: true

module JobTick
  class Configuration
    attr_accessor :api_key, :endpoint, :environment, :enabled

    def initialize
      @endpoint    = "https://api.jobtick.app/v1"
      @environment = ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "production"
      @enabled     = @environment == "production"
    end
  end
end
