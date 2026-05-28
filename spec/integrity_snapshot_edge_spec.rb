# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require_relative '../app/require_app'

describe 'IntegritySnapshot constraints' do
  before do
    SecureBidding::Database.migrate!
    SecureBidding::IntegritySnapshot.dataset.delete
    SecureBidding::Project.dataset.delete
  end

  it 'enforces unique snapshot per project' do
    project = SecureBidding::Project.create(title: 'unique-project', budget_cents: 2000)
    SecureBidding::IntegritySnapshot.create(project_id: project.id, canonical_hash: 'h1', snapshot_taken_at: Time.now)
    err = _{ SecureBidding::IntegritySnapshot.create(project_id: project.id, canonical_hash: 'h2', snapshot_taken_at: Time.now) }.must_raise(Sequel::DatabaseError)
    _(err.message).must_match /unique/i
  end
end
