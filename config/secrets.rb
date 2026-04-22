# frozen_string_literal: true

require 'yaml'
require_relative 'environments'

module SecureBidding
  module SecretsConfig
    module_function

    def database_key(env = SecureBidding::Environment.app_env)
      env_secrets = secrets_payload.fetch(env) do
        raise KeyError, "missing secrets for environment '#{env}'"
      end

      key = ENV.fetch('DATABASE_KEY', env_secrets.fetch('database_key'))
      raise ArgumentError, 'database_key must be exactly 32 bytes' unless key.to_s.b.bytesize == 32

      key
    end

    def secrets_payload
      @secrets_payload ||= begin
        path = [secrets_file_path, secrets_example_file_path, example_secrets_file_path]
               .find { |candidate| File.exist?(candidate) }
        YAML.safe_load(File.read(path), permitted_classes: [], aliases: false) || {}
      end
    end

    def secrets_file_path
      File.join(__dir__, 'secrets.yml')
    end

    def secrets_example_file_path
      File.join(__dir__, 'secrets-example.yml')
    end

    def example_secrets_file_path
      File.join(__dir__, 'example-secrets.yml')
    end
  end
end
