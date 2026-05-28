# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require_relative '../app/require_app'

describe 'SecureBidding::IntegritySnapshot' do
  before do
    SecureBidding::Database.migrate!
    SecureBidding::IntegritySnapshot.dataset.delete
    SecureBidding::Project.dataset.delete
  end

  it 'stores canonical hash and is associated with a project' do
    project = SecureBidding::Project.create(title: 'hash-project', budget_cents: 10_000)
    snapshot = SecureBidding::IntegritySnapshot.create(project_id: project.id, canonical_hash: 'abc123', snapshot_taken_at: Time.now)

    _(snapshot.project.id).must_equal project.id
    _(SecureBidding::IntegritySnapshot.first.canonical_hash).must_equal 'abc123'
  end
end
