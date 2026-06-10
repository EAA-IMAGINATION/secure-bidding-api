# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require_relative 'spec_helper'

describe SecureBidding::Policies::ProjectPolicy do
  before do
    SecureBidding::Database.migrate!
    SecureBidding::BidSubmission.dataset.delete
    SecureBidding::Project.dataset.delete
    SecureBidding::Account.dataset.delete
  end

  def policy_for(account, project)
    SecureBidding::Policies::ProjectPolicy.new(account, project)
  end

  def sample_client_envelope(label = 'secret')
    {
      ephemeralPublicKey: Base64.strict_encode64('e' * 32),
      nonce: Base64.strict_encode64('n' * 24),
      ciphertext: Base64.strict_encode64(label)
    }
  end

  def create_bid(project:, bidder:)
    bid = SecureBidding::BidSubmission.new(
      project_id: project.id,
      contractor_alias: bidder.username,
      bidder_account_id: bidder.id
    )
    bid.store_client_ciphertext(sample_client_envelope('amount'), sample_client_envelope('proposal'))
    bid.save
    bid
  end

  it 'allows available_for_bidding only while the deadline is still open' do
    open_project = SecureBidding::Project.create(
      title: 'open-bids',
      budget_cents: 10_000,
      state: 'published',
      bidding_deadline: Time.now + 3600
    )
    closed_project = SecureBidding::Project.create(
      title: 'closed-bids',
      budget_cents: 10_000,
      state: 'published',
      bidding_deadline: Time.now - 60
    )

    _(policy_for(nil, open_project).available_for_bidding?).must_equal true
    _(policy_for(nil, closed_project).available_for_bidding?).must_equal false
  end

  it 'tracks open bids only while bidding remains available' do
    bidder = SecureBidding::Account.new(username: 'bidder', system_role: 'member')
    bidder.set_password('secret')
    bidder.set_email('bidder@example.com')
    bidder.verify_email!
    bidder.save

    open_project = SecureBidding::Project.create(
      title: 'track-open',
      budget_cents: 10_000,
      state: 'published',
      bidding_deadline: Time.now + 3600
    )
    closed_project = SecureBidding::Project.create(
      title: 'track-closed',
      budget_cents: 10_000,
      state: 'published',
      bidding_deadline: Time.now - 60
    )

    create_bid(project: open_project, bidder: bidder)
    create_bid(project: closed_project, bidder: bidder)

    _(policy_for(bidder, open_project).track_open_bid?).must_equal true
    _(policy_for(bidder, closed_project).track_open_bid?).must_equal false
    _(policy_for(bidder, closed_project).has_bid_submission?).must_equal true
  end
end
