# frozen_string_literal: true

require "logger"
require_relative "jobtick/version"
require_relative "jobtick/configuration"
require_relative "jobtick/client"
require_relative "jobtick/monitor"
require_relative "jobtick/parsers/whenever"
require_relative "jobtick/parsers/solid_queue"
require_relative "jobtick/parsers/sidekiq"
require_relative "jobtick/registry"
require_relative "jobtick/railtie" if defined?(Rails::Railtie)

module JobTick
  class Error < StandardError; end

  class << self
    def configure
      yield config
    end

    def config
      @config ||= Configuration.new
    end

    def client
      @client ||= Client.new
    end

    def logger
      defined?(Rails) ? Rails.logger : Logger.new($stdout)
    end

    def reset!
      @config = nil
      @client = nil
    end
  end
end
