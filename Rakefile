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

    seed_dir = File.expand_path('app/db/seeds', __dir__)
    projects_seed_file = File.join(seed_dir, 'projects_seed.yml')
    bid_submissions_seed_file = File.join(seed_dir, 'bid_submissions_seed.yml')

    projects_payload = if File.exist?(projects_seed_file)
                         YAML.safe_load(File.read(projects_seed_file), permitted_classes: [], aliases: false) || {}
                       else
                         {}
                       end
    bid_submissions_payload = if File.exist?(bid_submissions_seed_file)
                                YAML.safe_load(
                                  File.read(bid_submissions_seed_file),
                                  permitted_classes: [],
                                  aliases: false
                                ) || {}
                              else
                                {}
                              end
    project_entries = projects_payload.fetch('projects', [])
    bid_submission_entries = bid_submissions_payload.fetch('bid_submissions', [])

    project_ids_by_title = {}
    project_entries.each do |entry|
      title = entry.fetch('title')
      budget_cents = entry.fetch('budget_cents')
      project = SecureBidding::Project.first(title: title) ||
                SecureBidding::Project.create(title: title, budget_cents: budget_cents)
      project_ids_by_title[title] = project.id
    end

    bid_submission_entries.each do |entry|
      project_id = entry['project_id'] || project_ids_by_title[entry['project_title']]
      raise "Seed bid submission '#{entry['contractor_alias']}' references an unknown project" if project_id.nil?

      contractor_alias = entry.fetch('contractor_alias')
      next if SecureBidding::BidSubmission.first(project_id: project_id, contractor_alias: contractor_alias)

      bid_submission = SecureBidding::BidSubmission.new(project_id: project_id, contractor_alias: contractor_alias)
      bid_submission.encrypt_bid(entry.fetch('plaintext_bid'))
      bid_submission.save
    end

    puts(
      "Seeded #{SecureBidding::Project.count} projects and " \
      "#{SecureBidding::BidSubmission.count} bid submissions in #{env}"
    )
  end
end

desc 'Launch pry with application code and models preloaded'
task :console do
  abort('pry is not available. Run bundle install in development environment.') unless defined?(Pry)

  require_relative 'app/require_app'

  puts "Loaded app in #{SecureBidding::Database.environment} environment"
  puts 'Examples: SecureBidding::Project.all, SecureBidding::BidSubmission.all'
  Pry.start
end
