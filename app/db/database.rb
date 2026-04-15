# frozen_string_literal: true

require 'sequel'
require 'fileutils'
require_relative '../../config/environments'

module SecureBidding
  # Centralized Sequel database configuration and migration helpers.
  module Database
    DB_DIR = File.expand_path(__dir__).freeze
    MIGRATIONS_DIR = File.join(DB_DIR, 'migrations').freeze

    module_function

    def environment
      SecureBidding::Environment.app_env
    end

    def db_file_for(env)
      File.join(DB_DIR, "#{env}.db")
    end

    def connect!(env = environment)
      FileUtils.mkdir_p(DB_DIR)
      SecureBidding.send(:remove_const, :DB) if SecureBidding.const_defined?(:DB)
      connection = if ENV.key?('DATABASE_URL')
                     Sequel.connect(SecureBidding::Environment.database_url)
                   else
                     Sequel.sqlite(db_file_for(env))
                   end
      SecureBidding.const_set(:DB, connection)
    end

    def db
      SecureBidding.const_defined?(:DB) ? SecureBidding::DB : connect!
    end

    def migrate!(env = environment)
      connect!(env) unless SecureBidding.const_defined?(:DB)
      Sequel.extension :migration
      Sequel::Migrator.run(db, MIGRATIONS_DIR)
    end
  end
end
