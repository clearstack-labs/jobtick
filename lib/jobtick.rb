# frozen_string_literal: true

require "logger"
require_relative "jobtick/version"
require_relative "jobtick/configuration"
require_relative "jobtick/client"
require_relative "jobtick/monitor"
require_relative "jobtick/parsers"
require_relative "jobtick/railtie" if defined?(Rails::Railtie)

module JobTick
  EMPTY_MAP = {}.freeze

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

    # The app's root directory, used to resolve schedule/recurring config
    # files. Falls back to the process's working directory when Rails isn't
    # loaded (or hasn't set a root yet) so discovery doesn't silently depend
    # on the caller's cwd.
    def root
      if defined?(Rails) && Rails.respond_to?(:root) && Rails.root
        Rails.root.to_s
      else
        Dir.pwd
      end
    end

    def logger
      (defined?(Rails) && Rails.logger) || (@fallback_logger ||= Logger.new($stdout))
    end

    def monitor_map
      @monitor_map ||= EMPTY_MAP
    end

    attr_writer :monitor_map

    def monitor_key_for(class_name)
      monitor_map[class_name]
    end

    def reset!
      Dispatcher.reset! if defined?(Dispatcher)
      @config = nil
      @client = nil
      @monitor_map = EMPTY_MAP
    end
  end
end
