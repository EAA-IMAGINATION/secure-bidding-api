# frozen_string_literal: true

require 'rake'
require 'rake/testtask'
require 'sequel'
require 'yaml'
require 'sequel/extensions/seed'
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

# rubocop:disable Metrics/BlockLength
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

  desc 'Clear app data in current environment (projects, bid submissions, bid files)'
  task :clear do
    require_relative 'app/require_app'

    env = SecureBidding::Database.environment
    SecureBidding::Database.connect!(env)
    SecureBidding::Database.migrate!(env)

    SecureBidding::BidSubmission.dataset.delete
    SecureBidding::Project.dataset.delete
    Dir.glob(File.expand_path('app/db/store/*.json', __dir__)).each { |file| File.delete(file) }

    puts "Cleared app data in #{env}"
  end

  desc 'Seed the current environment database with project and bid submission data'
  task :seed do
    require_relative 'app/require_app'

    env = SecureBidding::Database.environment
    SecureBidding::Database.connect!(env)
    SecureBidding::Database.migrate!(env)

    Sequel.extension :seed
    Sequel::Seed.setup(env.to_sym)
    Sequel::Seeder.apply(SecureBidding::Database.db, File.expand_path('seeds', __dir__))

    puts(
      "Seeded #{SecureBidding::Account.count} accounts, " \
      "#{SecureBidding::Project.count} projects, " \
      "#{SecureBidding::BidSubmission.count} bid submissions in #{env}"
    )
  end
end
# rubocop:enable Metrics/BlockLength

desc 'Setup and start the application (install deps, configure, migrate, seed, run server)'
task :start do
  puts 'Installing dependencies...'
  system('bundle install') || exit(1)

  puts 'Configuring secrets...'
  system('cp config/secrets-example.yml config/secrets.yml') unless File.exist?('config/secrets.yml')

  puts 'Creating store directory...'
  system('mkdir -p app/db/store')

  puts 'Running migrations...'
  Rake::Task['db:migrate'].invoke

  puts 'Seeding database...'
  Rake::Task['db:seed'].invoke

  puts "\n✓ Setup complete. Starting server on http://localhost:3000...\n"
  system('bundle exec rackup -p 3000')
end

desc 'Launch pry with application code and models preloaded'
task :console do
  abort('pry is not available. Run bundle install in development environment.') unless defined?(Pry)

  require_relative 'app/require_app'

  puts "Loaded app in #{SecureBidding::Database.environment} environment"
  puts 'Examples: SecureBidding::Project.all, SecureBidding::BidSubmission.all'
  Pry.start
end

desc 'Start the API server only (requires db:migrate and db:seed done first)'
task :server do
  puts "Starting server on http://localhost:3000..."
  system('bundle exec rackup -p 3000')
end

namespace :db do
  # Promote an existing account to admin role.
  # Usage: USERNAME=jdoe rake db:bootstrap_admin OR EMAIL=joe@example.com rake db:bootstrap_admin
  desc 'Promote an account to admin'
  task :bootstrap_admin do
    require_relative 'app/require_app'
    env = SecureBidding::Database.environment
    SecureBidding::Database.connect!(env)

    username = ENV['USERNAME']
    email = ENV['EMAIL']

    account = if username && !username.strip.empty?
                SecureBidding::Account.first(username: username.strip)
              elsif email && !email.strip.empty?
                SecureBidding::Account.first(email_hash: SecureBidding::Account.search_hash(email.strip))
              else
                abort 'Provide USERNAME or EMAIL env var, e.g., USERNAME=jdoe rake db:bootstrap_admin'
              end

    if account.nil?
      puts 'Account not found'
      exit 1
    end

    result = SecureBidding::Services::Accounts::UpdateAccount.call(account, system_role: 'admin')

    if result.is_a?(Hash) && result[:ok]
      puts "Assigned system_role admin to account #{account.username} (#{account.id})"
    else
      puts "Failed to assign role: #{result[:error] || 'unknown error'}"
      exit 1
    end
  end
end

task bootstrap_admin: 'db:bootstrap_admin'
