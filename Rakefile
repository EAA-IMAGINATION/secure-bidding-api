# frozen_string_literal: true

require 'rake'
require 'rake/testtask'
require 'sequel'
require 'yaml'
require_relative 'app/db/database'

begin
  require 'pry'
rescue LoadError
  # console task can still instruct to install development dependencies
end

task default: :spec

desc 'Run all specs'
Rake::TestTask.new(:spec) do |t|
  t.pattern = 'spec/*_spec.rb'
  t.warning = false
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

  desc 'Clear app data in current environment (accounts, secrets, bid files)'
  task :clear do
    require_relative 'app/require_app'

    env = SecureBidding::Database.environment
    SecureBidding::Database.connect!(env)
    SecureBidding::Database.migrate!(env)

    SecureBidding::Secret.dataset.delete
    SecureBidding::Account.dataset.delete
    Dir.glob(File.expand_path('app/db/store/*.json', __dir__)).each { |file| File.delete(file) }

    puts "Cleared app data in #{env}"
  end

  desc 'Seed the current environment database with account and secret data'
  task :seed do
    require_relative 'app/require_app'

    env = SecureBidding::Database.environment
    SecureBidding::Database.connect!(env)
    SecureBidding::Database.migrate!(env)

    seed_dir = File.expand_path('app/db/seeds', __dir__)
    accounts_seed_file = File.join(seed_dir, 'accounts_seed.yml')
    secrets_seed_file = File.join(seed_dir, 'secrets_seed.yml')

    accounts_payload = if File.exist?(accounts_seed_file)
                         YAML.safe_load(File.read(accounts_seed_file), permitted_classes: [], aliases: false) || {}
                       else
                         {}
                       end
    secrets_payload = if File.exist?(secrets_seed_file)
                        YAML.safe_load(File.read(secrets_seed_file), permitted_classes: [], aliases: false) || {}
                      else
                        {}
                      end
    account_entries = accounts_payload.fetch('accounts', [])
    secret_entries = secrets_payload.fetch('secrets', [])

    account_ids_by_username = {}
    account_entries.each do |entry|
      username = entry.fetch('username')
      email = entry.fetch('email')
      account = SecureBidding::Account.first(username: username) ||
                SecureBidding::Account.create(username: username, email: email)
      account_ids_by_username[username] = account.id
    end

    secret_entries.each do |entry|
      account_id = entry['account_id'] || account_ids_by_username[entry['account_username']]
      raise "Seed secret '#{entry['title']}' references an unknown account" if account_id.nil?

      title = entry.fetch('title')
      next if SecureBidding::Secret.first(account_id: account_id, title: title)

      secret = SecureBidding::Secret.new(account_id: account_id, title: title)
      secret.encrypt_data(entry.fetch('plaintext'))
      secret.save
    end

    puts "Seeded #{SecureBidding::Account.count} accounts and #{SecureBidding::Secret.count} secrets in #{env}"
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
