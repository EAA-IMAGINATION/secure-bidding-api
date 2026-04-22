# frozen_string_literal: true

require 'figaro'

module SecureBidding
  module Environment
    module_function

    def app_env
      ENV.fetch('RACK_ENV', 'development')
    end

    def database_url(env = app_env)
      load_secrets!(env)
      ENV.delete('DATABASE_URL') || "sqlite://app/db/#{env}.db"
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
  end
end
