# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require_relative '../app/require_app'

describe 'SecureBidding::BidSubmission' do
  before do
    SecureBidding::Database.migrate!
    SecureBidding::BidSubmission.dataset.delete
    SecureBidding::Project.dataset.delete
  end

  it 'encrypts plaintext bid and decrypts it back with the same key' do
    project = SecureBidding::Project.create(title: 'alice-project', budget_cents: 70_000)
    bid_submission = SecureBidding::BidSubmission.new(project_id: project.id, contractor_alias: 'alice')

    bid_submission.encrypt_bid('my-plaintext-password')
    bid_submission.save

    stored = SecureBidding::BidSubmission.first
    _(stored.secure_encrypted_bid).wont_equal 'my-plaintext-password'
    _(stored.decrypt_bid).must_equal 'my-plaintext-password'
  end

  it 'belongs to project and project has many bid submissions' do
    project = SecureBidding::Project.create(title: 'bob-project', budget_cents: 80_000)
    bid_submission = SecureBidding::BidSubmission.new(project_id: project.id, contractor_alias: 'bob')
    bid_submission.encrypt_bid('ciphertext')
    bid_submission.save

    _(bid_submission.project.id).must_equal project.id
    _(project.bid_submissions.map(&:id)).must_include bid_submission.id
  end
end
