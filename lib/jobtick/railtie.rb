# frozen_string_literal: true

module JobTick
  class Railtie < Rails::Railtie
    initializer "jobtick.sync_registry" do
      ActiveSupport.on_load(:after_initialize) do
        next unless JobTick.config.enabled

        JobTick::Registry.sync
      end
    end

    rake_tasks do
      load File.expand_path("../tasks/jobtick.rake", __dir__)
    end
  end
end
