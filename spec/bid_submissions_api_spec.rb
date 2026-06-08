# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require_relative 'spec_helper'
require 'cgi'

describe 'API /api/v1/bid_submissions' do
  include Rack::Test::Methods

  def app
    SecureBidding::App.freeze.app
  end

  def create_account(username:, email:)
    account = SecureBidding::Account.new(username: username, system_role: 'member')
    account.set_password('my-secret-pass')
    account.set_email(email)
    account.save
    account.verify_email! if account.email_verified_at.nil?
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
    SecureBidding::ProjectMembership.dataset.delete if SecureBidding::Database.db.table_exists?(:project_memberships)
    SecureBidding::Account.dataset.delete if SecureBidding::Database.db.table_exists?(:accounts)
    SecureBidding::BidSubmission.dataset.delete
    SecureBidding::Project.dataset.delete
  end

  it 'HAPPY: returns all bid submissions metadata from GET /api/v1/bid_submissions' do
    owner = create_account(username: 'list-owner', email: 'list-owner@example.com')
    project = SecureBidding::Project.create(
      title: 'list-project',
      budget_cents: 120_000,
      state: 'published',
      bidding_deadline: Time.now - 60
    )
    owner_role = SecureBidding::Role.ensure_role('project_owner')
    SecureBidding::ProjectMembership.create(account_id: owner.id, project_id: project.id, role_id: owner_role.id)
    bid_submission = SecureBidding::BidSubmission.new(project_id: project.id, contractor_alias: 'api-key-labs')
    bid_submission.encrypt_bid('payload-1')
    bid_submission.save

    get '/api/v1/bid_submissions', '', auth_header_for(owner)

    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['bid_submissions']).must_be_kind_of Array
    _(response_body['bid_submissions'].length).must_equal 1
    _(response_body['bid_submissions'][0]['id']).must_equal bid_submission.id
    _(response_body['bid_submissions'][0]['project_id']).must_equal project.id
    _(response_body['bid_submissions'][0]['contractor_alias']).must_equal 'api-key-labs'
    _(response_body['bid_submissions'][0].key?('secure_encrypted_bid')).must_equal false
  end

  it 'HAPPY: returns 201 and stores encrypted payload for valid payload' do
    project = SecureBidding::Project.create(title: 'route-project', budget_cents: 333_000, state: 'published')
    bidder = create_account(username: 'route-bidder', email: 'route-bidder@example.com')
    payload = {
      project_id: project.id,
      contractor_alias: 'route-user'
    }.merge(sample_client_bid_payload('p@ssw0rd'))

    post '/api/v1/bid_submissions', payload.to_json, auth_header_for(bidder)

    _(last_response.status).must_equal 201
    response_body = JSON.parse(last_response.body)
    _(response_body['id']).wont_be_nil
    _(response_body['status']).must_equal 'created'

    stored = SecureBidding::BidSubmission[response_body['id']]
    _(stored).wont_be_nil
    _(stored.encrypted_bid_amount).wont_be_nil
    _(stored.encrypted_proposal_text).wont_be_nil
  end

  it 'SAD: returns 400 for invalid payload' do
    post '/api/v1/bid_submissions',
         { contractor_alias: 'missing project' }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_be_kind_of Hash
    _(response_body['error']['project_id']).wont_be_nil
    _(response_body['error']['encrypted_bid_amount']).wont_be_nil
  end

  it 'HAPPY: returns bid submission metadata for an existing id' do
    owner = create_account(username: 'meta-owner', email: 'meta-owner@example.com')
    project = SecureBidding::Project.create(
      title: 'meta-project',
      budget_cents: 10_000,
      state: 'published',
      bidding_deadline: Time.now - 60
    )
    owner_role = SecureBidding::Role.ensure_role('project_owner')
    SecureBidding::ProjectMembership.create(account_id: owner.id, project_id: project.id, role_id: owner_role.id)
    bid_submission = SecureBidding::BidSubmission.new(project_id: project.id, contractor_alias: 'meta-user')
    bid_submission.encrypt_bid('token-123')
    bid_submission.save

    get "/api/v1/bid_submissions/#{bid_submission.id}", '', auth_header_for(owner)

    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['id']).must_equal bid_submission.id
    _(response_body['project_id']).must_equal project.id
    _(response_body['contractor_alias']).must_equal 'meta-user'
    _(response_body.key?('secure_encrypted_bid')).must_equal false
  end

  it 'SAD: returns 404 for missing bid submission id' do
    get '/api/v1/bid_submissions/00000000-0000-0000-0000-000000000000'

    _(last_response.status).must_equal 404
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'Bid submission not found'
  end

  it 'SAD: ignores mass-assigned id for bid submission creation' do
    project = SecureBidding::Project.create(title: 'locked-project', budget_cents: 45_000, state: 'published')
    bidder = create_account(username: 'locked-bidder', email: 'locked-bidder@example.com')
    payload = {
      project_id: project.id,
      contractor_alias: 'locked-user',
      id: '00000000-0000-0000-0000-000000000099'
    }.merge(sample_client_bid_payload('p@ssw0rd'))

    post '/api/v1/bid_submissions', payload.to_json, auth_header_for(bidder)

    _(last_response.status).must_equal 201
    response_body = JSON.parse(last_response.body)
    _(response_body['id']).wont_equal '00000000-0000-0000-0000-000000000099'
    _(SecureBidding::BidSubmission['00000000-0000-0000-0000-000000000099']).must_be_nil
  end

  it 'SAD: rejects SQL injection string in project_id for bid submission creation' do
    payload = {
      project_id: "00000000-0000-0000-0000-000000000000' OR 1=1 --",
      contractor_alias: 'db-password'
    }.merge(sample_client_bid_payload('p@ssw0rd'))

    post '/api/v1/bid_submissions', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'project_id must be a UUID'
  end

  it 'SAD: rejects SQL injection string in bid submission id route' do
    get "/api/v1/bid_submissions/#{CGI.escape("00000000-0000-0000-0000-000000000000' OR 1=1 --")}"

    _(last_response.status).must_equal 404
  end

  it 'SAD: rejects bid submission for saved projects' do
    project = SecureBidding::Project.create(title: 'saved-only-project', budget_cents: 77_000, state: 'saved')
    bidder = create_account(username: 'saved-bidder', email: 'saved-bidder@example.com')
    payload = {
      project_id: project.id,
      contractor_alias: 'blocked-bidder'
    }.merge(sample_client_bid_payload('will-not-save'))

    post '/api/v1/bid_submissions', payload.to_json, auth_header_for(bidder)

    _(last_response.status).must_equal 403
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'Project is not open for bidding'
  end

  it 'SAD: rejects bid submission without login' do
    project = SecureBidding::Project.create(title: 'login-required-project', budget_cents: 99_000, state: 'published')
    payload = {
      project_id: project.id,
      contractor_alias: 'anonymous'
    }.merge(sample_client_bid_payload('not-allowed'))

    post '/api/v1/bid_submissions', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 401
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'Login required to bid on projects'
  end
end
