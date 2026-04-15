# frozen_string_literal: true

require 'rake'
require 'sequel'
require_relative 'app/db/database'

begin
  require 'pry'
rescue LoadError
  # console task can still instruct to install development dependencies
end

namespace :db do
  desc 'Run Sequel migrations for development and test sqlite databases'
  task :migrate do
    %w[development test].each do |env|
      SecureBidding::Database.connect!(env)
      SecureBidding::Database.migrate!(env)
      puts "Migrated #{SecureBidding::Database.db_file_for(env)}"
    end
  end

  desc 'Create development and test sqlite databases if missing'
  task :create do
    %w[development test].each do |env|
      db_path = SecureBidding::Database.db_file_for(env)
      next if File.exist?(db_path)

      SecureBidding::Database.connect!(env)
      puts "Created #{db_path}"
    end
  end

  desc 'Drop development and test sqlite databases'
  task :drop do
    %w[development test].each do |env|
      db_path = SecureBidding::Database.db_file_for(env)
      File.delete(db_path) if File.exist?(db_path)
      puts "Dropped #{db_path}"
    end
  end

  desc 'Reset development and test sqlite databases'
  task reset: %i[drop migrate]

  desc 'Show latest migration versions for development and test'
  task :version do
    %w[development test].each do |env|
      SecureBidding::Database.connect!(env)
      version = if SecureBidding::DB.table_exists?(:schema_info)
                  SecureBidding::DB[:schema_info].get(:version)
                else
                  0
                end
      puts "#{env}: #{version}"
    end
  end
end

desc 'Launch pry with application code and models preloaded'
task :console do
  abort('pry is not available. Run bundle install in development environment.') unless defined?(Pry)

  require_relative 'app/require_app'

  puts "Loaded app in #{SecureBidding::Database.environment} environment"
  puts 'Examples: SecureBidding::Account.all, SecureBidding::Secret.all'
  Pry.start
end
