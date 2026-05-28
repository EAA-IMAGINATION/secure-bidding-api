# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'digest'
require_relative '../app/require_app'

describe 'GenerateIntegritySnapshot service' do
  before do
    SecureBidding::Database.migrate!
    SecureBidding::IntegritySnapshot.dataset.delete
    SecureBidding::BidSubmission.dataset.delete
    SecureBidding::Project.dataset.delete
  end

  it 'generates canonical hash from bid submissions and documents' do
    project = SecureBidding::Project.create(title: 'snapshot-project', budget_cents: 3000)

    bs1 = SecureBidding::BidSubmission.new(project_id: project.id, contractor_alias: 'a')
    bs1.encrypt_bid('secret1')
    bs1.save

    bs2 = SecureBidding::BidSubmission.new(project_id: project.id, contractor_alias: 'b')
    bs2.encrypt_bid('secret2')
    bs2.save

    # Attach a document to bs2
    SecureBidding::BidDocument.create(bid_id: bs2.id, file_name_secure: 'n', file_hash: 'doc1', storage_path: 'p')

    # Manually compute expected canonical
    parts1 = [bs1.secure_encrypted_bid.to_s]
    hash1 = Digest::SHA256.hexdigest(parts1.join)

    parts2 = [bs2.secure_encrypted_bid.to_s, 'doc1']
    hash2 = Digest::SHA256.hexdigest(parts2.join)

    expected = Digest::SHA256.hexdigest([hash1, hash2].sort.join)

    SecureBidding::Services::Projects::GenerateIntegritySnapshot.call(project)

    snapshot = SecureBidding::IntegritySnapshot.first
    _(snapshot.canonical_hash).must_equal expected
  end
end
