# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'json'
require_relative '../app/require_app'

# rubocop:disable Metrics/BlockLength
describe 'API role and payment placeholders' do
  include Rack::Test::Methods

  def app
    SecureBidding::App.freeze.app
  end

  def create_account(username:, email:)
    account = SecureBidding::Account.new(username: username, system_role: 'member')
    account.set_password('my-secret-pass')
    account.set_email(email)
    account.save
    account
  end

  before do
    SecureBidding::Database.migrate!
    db = SecureBidding::Database.db
    db[:payments].delete if db.table_exists?(:payments)
    db[:project_memberships].delete if db.table_exists?(:project_memberships)
    db[:account_roles].delete if db.table_exists?(:account_roles)
    db[:roles].delete if db.table_exists?(:roles)
    SecureBidding::BidSubmission.dataset.delete
    SecureBidding::Project.dataset.delete
    SecureBidding::AccountProject.dataset.delete
    SecureBidding::Account.dataset.delete
  end

  it 'HAPPY: assigns and lists system roles for an account' do
    account = create_account(username: 'role-user', email: 'role-user@example.com')

    post "/api/v1/accounts/#{account.id}/system_roles",
         { role: 'system_admin' }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 201

    get "/api/v1/accounts/#{account.id}/system_roles"
    _(last_response.status).must_equal 200
    body = JSON.parse(last_response.body)
    _(body['roles']).must_include 'system_admin'
  end

  it 'HAPPY: creates project requirement with a project_owner account' do
    owner = create_account(username: 'owner-user', email: 'owner-user@example.com')

    post "/api/v1/accounts/#{owner.id}/system_roles",
         { role: 'project_owner' }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }
    _(last_response.status).must_equal 201

    post '/api/v1/projects',
         {
           title: 'owner-scoped-project',
           budget_cents: 100_000,
           owner_account_id: owner.id
         }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 201
    project_id = JSON.parse(last_response.body)['id']

    get "/api/v1/projects/#{project_id}/memberships"
    _(last_response.status).must_equal 200
    memberships = JSON.parse(last_response.body)['memberships']
    owner_membership = memberships.find { |entry| entry['account_id'] == owner.id }
    _(owner_membership['role']).must_equal 'project_owner'
  end

  it 'HAPPY: allows bidder membership to create project bid' do
    owner = create_account(username: 'owner-two', email: 'owner-two@example.com')
    bidder = create_account(username: 'bidder-one', email: 'bidder-one@example.com')

    post "/api/v1/accounts/#{owner.id}/system_roles",
         { role: 'project_owner' }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }
    _(last_response.status).must_equal 201

    post '/api/v1/projects',
         {
           title: 'bid-project',
           budget_cents: 200_000,
           owner_account_id: owner.id
         }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }
    _(last_response.status).must_equal 201
    project_id = JSON.parse(last_response.body)['id']

    post "/api/v1/projects/#{project_id}/memberships",
         {
           account_id: bidder.id,
           role: 'bidder'
         }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }
    _(last_response.status).must_equal 201

    post "/api/v1/projects/#{project_id}/bids",
         {
           bidder_account_id: bidder.id,
           contractor_alias: 'acme-bidder',
           plaintext_bid: 'secret-bid'
         }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 201
    response = JSON.parse(last_response.body)
    _(response['id']).wont_be_nil
  end

  it 'SAD: rejects bid creation by account without bidder membership' do
    owner = create_account(username: 'owner-three', email: 'owner-three@example.com')
    outsider = create_account(username: 'outsider', email: 'outsider@example.com')

    post "/api/v1/accounts/#{owner.id}/system_roles",
         { role: 'project_owner' }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }
    _(last_response.status).must_equal 201

    post '/api/v1/projects',
         {
           title: 'restricted-bid-project',
           budget_cents: 300_000,
           owner_account_id: owner.id
         }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }
    _(last_response.status).must_equal 201
    project_id = JSON.parse(last_response.body)['id']

    post "/api/v1/projects/#{project_id}/bids",
         {
           bidder_account_id: outsider.id,
           contractor_alias: 'not-allowed',
           plaintext_bid: 'should-fail'
         }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 403
  end

  it 'HAPPY: creates and updates payment placeholder status' do
    owner = create_account(username: 'owner-four', email: 'owner-four@example.com')
    bidder = create_account(username: 'bidder-two', email: 'bidder-two@example.com')

    post "/api/v1/accounts/#{owner.id}/system_roles",
         { role: 'project_owner' }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }
    _(last_response.status).must_equal 201

    post '/api/v1/projects',
         {
           title: 'payment-project',
           budget_cents: 400_000,
           owner_account_id: owner.id
         }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }
    _(last_response.status).must_equal 201
    project_id = JSON.parse(last_response.body)['id']

    post "/api/v1/projects/#{project_id}/memberships",
         {
           account_id: bidder.id,
           role: 'bidder'
         }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }
    _(last_response.status).must_equal 201

    post "/api/v1/projects/#{project_id}/bids",
         {
           bidder_account_id: bidder.id,
           contractor_alias: 'payment-bidder',
           plaintext_bid: 'payment-secret-bid'
         }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }
    _(last_response.status).must_equal 201
    bid_submission_id = JSON.parse(last_response.body)['id']

    post '/api/v1/payments',
         {
           bid_submission_id: bid_submission_id,
           paid: false,
           method: 'placeholder',
           reference: 'stub-001'
         }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }
    _(last_response.status).must_equal 201
    payment_id = JSON.parse(last_response.body)['id']

    patch "/api/v1/payments/#{payment_id}",
          { paid: true }.to_json,
          { 'CONTENT_TYPE' => 'application/json' }
    _(last_response.status).must_equal 200

    get "/api/v1/payments/#{payment_id}"
    _(last_response.status).must_equal 200
    payment_payload = JSON.parse(last_response.body)
    _(payment_payload['paid']).must_equal true
  end
end
# rubocop:enable Metrics/BlockLength
