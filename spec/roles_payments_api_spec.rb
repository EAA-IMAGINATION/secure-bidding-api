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

  def auth_header_for(account)
    token = SecureBidding::AuthToken.tokenize(
      { account_id: account.id, username: account.username, system_role: account.system_role },
      SecureBidding::AuthToken::ONE_HOUR
    )
    { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
  end

  before do
    SecureBidding::AuthToken.setup(SecureBidding::AuthToken.generate_key)
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

    # Create admin account for role assignments
    @admin = SecureBidding::Account.new(username: 'admin-user', system_role: 'admin')
    @admin.set_password('admin-password')
    @admin.set_email('admin@example.com')
    @admin.save
  end

  it 'HAPPY: assigns and lists system roles for an account' do
    account = create_account(username: 'role-user', email: 'role-user@example.com')

    post "/api/v1/accounts/#{account.id}/system_roles",
         { role: 'system_admin' }.to_json,
         auth_header_for(@admin)

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
         auth_header_for(@admin)
    _(last_response.status).must_equal 201

    post '/api/v1/projects',
         {
           title: 'owner-scoped-project',
           budget_cents: 100_000
         }.to_json,
         auth_header_for(owner)

    _(last_response.status).must_equal 201
    project_id = JSON.parse(last_response.body)['id']

    get "/api/v1/projects/#{project_id}/memberships"
    _(last_response.status).must_equal 200
    memberships = JSON.parse(last_response.body)['memberships']
    owner_membership = memberships.find { |entry| entry['account_id'] == owner.id }
    _(owner_membership['role']).must_equal 'project_owner'
  end

  it 'HAPPY: allows any account to bid on a published project without membership' do
    owner = create_account(username: 'owner-two', email: 'owner-two@example.com')
    bidder = create_account(username: 'bidder-one', email: 'bidder-one@example.com')

    post "/api/v1/accounts/#{owner.id}/system_roles",
         { role: 'project_owner' }.to_json,
         auth_header_for(@admin)
    _(last_response.status).must_equal 201

    post '/api/v1/projects',
         {
           title: 'bid-project',
           budget_cents: 200_000,
           state: 'published'
         }.to_json,
         auth_header_for(owner)
    _(last_response.status).must_equal 201
    project_id = JSON.parse(last_response.body)['id']

    post "/api/v1/projects/#{project_id}/bids",
         {
           bidder_account_id: bidder.id,
           contractor_alias: 'acme-bidder',
           plaintext_bid: 'secret-bid'
         }.to_json,
         auth_header_for(bidder)

    _(last_response.status).must_equal 201
    response = JSON.parse(last_response.body)
    _(response['id']).wont_be_nil
  end

  it 'SAD: rejects bidding on saved project state' do
    owner = create_account(username: 'owner-three', email: 'owner-three@example.com')
    outsider = create_account(username: 'outsider', email: 'outsider@example.com')

    post "/api/v1/accounts/#{owner.id}/system_roles",
         { role: 'project_owner' }.to_json,
         auth_header_for(@admin)
    _(last_response.status).must_equal 201

    post '/api/v1/projects',
         {
           title: 'restricted-bid-project',
           budget_cents: 300_000
         }.to_json,
         auth_header_for(owner)
    _(last_response.status).must_equal 201
    project_id = JSON.parse(last_response.body)['id']

    post "/api/v1/projects/#{project_id}/bids",
         {
           bidder_account_id: outsider.id,
           contractor_alias: 'not-allowed',
           plaintext_bid: 'should-fail'
         }.to_json,
         auth_header_for(outsider)

    _(last_response.status).must_equal 403
    response = JSON.parse(last_response.body)
    _(response['error']).must_equal 'Project is not open for bidding'
  end

  it 'SAD: rejects project owner bidding on own published project' do
    owner = create_account(username: 'owner-self-bid', email: 'owner-self-bid@example.com')

    post "/api/v1/accounts/#{owner.id}/system_roles",
         { role: 'project_owner' }.to_json,
         auth_header_for(@admin)
    _(last_response.status).must_equal 201

    post '/api/v1/projects',
         {
           title: 'self-owned-project',
           budget_cents: 310_000,
           state: 'published'
         }.to_json,
         auth_header_for(owner)
    _(last_response.status).must_equal 201
    project_id = JSON.parse(last_response.body)['id']

    post "/api/v1/projects/#{project_id}/bids",
         {
           bidder_account_id: owner.id,
           contractor_alias: 'self-owner',
           plaintext_bid: 'should-be-rejected'
         }.to_json,
         auth_header_for(owner)

    _(last_response.status).must_equal 403
    response = JSON.parse(last_response.body)
    _(response['error']).must_equal 'Project owner cannot bid on own project'
  end

  it 'HAPPY: creates and updates payment placeholder status' do
    owner = create_account(username: 'owner-four', email: 'owner-four@example.com')
    bidder = create_account(username: 'bidder-two', email: 'bidder-two@example.com')

    post "/api/v1/accounts/#{owner.id}/system_roles",
         { role: 'project_owner' }.to_json,
         auth_header_for(@admin)
    _(last_response.status).must_equal 201

    post '/api/v1/projects',
         {
           title: 'payment-project',
           budget_cents: 400_000,
           state: 'published'
         }.to_json,
         auth_header_for(owner)
    _(last_response.status).must_equal 201
    project_id = JSON.parse(last_response.body)['id']

    post "/api/v1/projects/#{project_id}/bids",
         {
           bidder_account_id: bidder.id,
           contractor_alias: 'payment-bidder',
           plaintext_bid: 'payment-secret-bid'
         }.to_json,
         auth_header_for(bidder)
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

  it 'SAD: rejects a non-UUID bid_submission_id when creating a payment' do
    post '/api/v1/payments',
         {
           bid_submission_id: 'not-a-uuid',
           paid: false,
           method: 'placeholder',
           reference: 'stub-002'
         }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'bid_submission_id must be a UUID'
  end

  it 'SAD: rejects a non-UUID account_id when assigning a project role' do
    owner = create_account(username: 'uuid-owner', email: 'uuid-owner@example.com')

    post "/api/v1/accounts/#{owner.id}/system_roles",
         { role: 'project_owner' }.to_json,
         auth_header_for(@admin)
    _(last_response.status).must_equal 201

    post '/api/v1/projects',
         {
           title: 'uuid-role-project',
           budget_cents: 210_000
         }.to_json,
         auth_header_for(owner)
    _(last_response.status).must_equal 201
    project_id = JSON.parse(last_response.body)['id']

    post "/api/v1/projects/#{project_id}/memberships",
         { account_id: 'not-a-uuid', role: 'bidder' }.to_json,
         auth_header_for(owner)

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'account_id must be a UUID'
  end
end
# rubocop:enable Metrics/BlockLength
