# frozen_string_literal: true

require 'yaml'
require_relative 'environments'

module SecureBidding
  # Loads per-environment secret configuration for encryption key management.
  module SecretsConfig
    module_function

    def database_key(env = SecureBidding::Environment.app_env)
      @database_keys ||= {}
      return @database_keys[env] if @database_keys.key?(env)

      key = runtime_database_key || file_database_key(env)
      validate_database_key!(key)

      @database_keys[env] = key
    end

    def runtime_database_key
      return nil unless ENV.key?('DATABASE_KEY') && !ENV['DATABASE_KEY'].to_s.empty?

      ENV.delete('DATABASE_KEY')
    end

    def file_database_key(env)
      env_secrets = secrets_payload.fetch(env) do
        raise KeyError, "missing secrets for environment '#{env}'"
      end

      env_secrets.fetch('database_key')
    end

    def validate_database_key!(key)
      raise ArgumentError, 'database_key must be exactly 32 bytes' unless key.to_s.b.bytesize == 32
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
