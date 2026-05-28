# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require_relative '../app/require_app'

describe 'SecureBidding::BidDocument' do
  before do
    SecureBidding::Database.migrate!
    SecureBidding::BidDocument.dataset.delete
    SecureBidding::BidSubmission.dataset.delete
    SecureBidding::Project.dataset.delete
  end

  it 'can be attached to a bid submission and stores file hash' do
    project = SecureBidding::Project.create(title: 'doc-project', budget_cents: 5_000)
    bid_sub = SecureBidding::BidSubmission.new(project_id: project.id, contractor_alias: 'carol')
    bid_sub.encrypt_bid('ciphertext')
    bid_sub.save

    doc = SecureBidding::BidDocument.create(bid_id: bid_sub.id, file_name_secure: 'enc_name', file_hash: 'deadbeef', storage_path: 'app/db/store/somefile')

    _(doc.bid_submission.id).must_equal bid_sub.id
    _(SecureBidding::BidDocument.first.file_hash).must_equal 'deadbeef'
  end
end
