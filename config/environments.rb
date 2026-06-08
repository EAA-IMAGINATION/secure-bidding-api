# frozen_string_literal: true

require 'figaro'

module SecureBidding
  # Helpers for loading environment-specific configuration and secrets.
  module Environment
    module_function

    def app_env
      ENV.fetch('RACK_ENV', 'development')
    end

    def database_url(env = app_env)
      # Prefer an explicit DATABASE_URL (e.g., provided by Heroku). Check it first
      return ENV['DATABASE_URL'] if ENV['DATABASE_URL'] && !ENV['DATABASE_URL'].to_s.strip.empty?

      # Fallback to secrets file values, then to local sqlite file
      load_secrets!(env)
      ENV['DATABASE_URL'] || "sqlite://app/db/#{env}.db"
    end

    def load_secrets!(env = app_env)
      return if @loaded_env == env

      Figaro.application = Figaro::Application.new(
        environment: env,
        path: secrets_path
      )
      Figaro.load
      @loaded_env = env
    end

    def secrets_path
      preferred = File.expand_path('secrets.yml', __dir__)
      return preferred if File.exist?(preferred)

      alternate = File.expand_path('secrets-example.yml', __dir__)
      return alternate if File.exist?(alternate)

      File.expand_path('example-secrets.yml', __dir__)
    end

    def env_value(*keys, default: nil)
      load_secrets!
      keys.flatten.each do |key|
        [key, key.to_s.upcase, key.to_s.downcase].map(&:to_s).uniq.each do |name|
          val = ENV[name]
          return val if val && !val.to_s.strip.empty?
        end
      end
      default
    end
  end
end
