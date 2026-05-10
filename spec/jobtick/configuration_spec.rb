# frozen_string_literal: true

require "spec_helper"

RSpec.describe JobTick::Configuration do
  subject(:config) { described_class.new }

  # Temporarily set ENV keys and restore after the block
  def with_env(vars, &example)
    saved = vars.each_key.with_object({}) { |k, h| h[k] = ENV.fetch(k, nil) }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    example.call
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  describe "defaults" do
    it "sets endpoint to the jobtick API" do
      expect(config.endpoint).to eq("https://api.jobtick.app/v1")
    end

    it "reads environment from RAILS_ENV" do
      with_env("RAILS_ENV" => "staging", "RACK_ENV" => nil) do
        expect(described_class.new.environment).to eq("staging")
      end
    end

    it "falls back to RACK_ENV when RAILS_ENV is absent" do
      with_env("RAILS_ENV" => nil, "RACK_ENV" => "staging") do
        expect(described_class.new.environment).to eq("staging")
      end
    end

    it "is enabled by default in production" do
      with_env("RAILS_ENV" => "production") do
        expect(described_class.new.enabled).to be(true)
      end
    end

    it "is disabled by default outside production" do
      with_env("RAILS_ENV" => "development") do
        expect(described_class.new.enabled).to be(false)
      end
    end

    it "has no api_key by default" do
      expect(config.api_key).to be_nil
    end

    it "has prune disabled by default" do
      expect(config.prune).to be(false)
    end
  end

  describe "customisation" do
    it "allows overriding all attributes" do
      config.api_key     = "secret"
      config.endpoint    = "https://custom.example.com/v2"
      config.environment = "staging"
      config.enabled     = true

      expect(config.api_key).to eq("secret")
      expect(config.endpoint).to eq("https://custom.example.com/v2")
      expect(config.environment).to eq("staging")
      expect(config.enabled).to be(true)
    end
  end
end
