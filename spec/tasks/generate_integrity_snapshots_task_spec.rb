# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rake'
require_relative '../../app/require_app'

# Load the rake task
load File.expand_path('../../../lib/tasks/generate_integrity_snapshots.rake', __FILE__)

Rake::Task.define_task(:environment)

describe 'db:generate_integrity_snapshots rake task' do
  before do
    SecureBidding::Database.migrate!
    SecureBidding::IntegritySnapshot.dataset.delete
    SecureBidding::BidSubmission.dataset.delete
    SecureBidding::Project.dataset.delete
  end

  it 'creates snapshots for projects past deadline' do
    project = SecureBidding::Project.create(title: 'task-snap', budget_cents: 4000, bidding_deadline: Time.now - 60)

    bs = SecureBidding::BidSubmission.new(project_id: project.id, contractor_alias: 'x')
    bs.encrypt_bid('secret')
    bs.save

    # Ensure no snapshot exists
    _(SecureBidding::IntegritySnapshot.count).must_equal 0

    Rake::Task['db:generate_integrity_snapshots'].reenable
    Rake::Task['db:generate_integrity_snapshots'].invoke

    _(SecureBidding::IntegritySnapshot.count).must_equal 1
    snapshot = SecureBidding::IntegritySnapshot.first
    _(snapshot.project_id).must_equal project.id
  end
end
