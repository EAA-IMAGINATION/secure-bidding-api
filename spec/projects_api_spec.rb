# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require_relative 'spec_helper'
require 'cgi'

describe 'API /api/v1/projects' do
  include Rack::Test::Methods

  def app
    SecureBidding::App.freeze.app
  end

  def create_account(username:, email:, verified: true)
    account = SecureBidding::Account.new(username: username, system_role: 'member')
    account.set_password('my-secret-pass')
    account.set_email(email)
    account.save
    account.verify_email! if verified && account.email_verified_at.nil?
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

  it 'HAPPY: creates a project with POST /api/v1/projects' do
    account = create_account(username: 'creator1', email: 'creator1@example.com')
    
    post '/api/v1/projects',
         { title: 'demo-project', budget_cents: 25_000 }.to_json,
         auth_header_for(account)

    _(last_response.status).must_equal 201
    response_body = JSON.parse(last_response.body)
    _(response_body['id']).wont_be_nil
    _(response_body['status']).must_equal 'created'
    stored = SecureBidding::Project[response_body['id']]
    _(stored.state).must_equal 'saved'
  end

  it 'HAPPY: creates a published project when state=published is provided' do
    account = create_account(username: 'creator2', email: 'creator2@example.com')
    
    post '/api/v1/projects',
         { title: 'published-project', budget_cents: 33_000, state: 'published' }.to_json,
         auth_header_for(account)

    _(last_response.status).must_equal 201
    response_body = JSON.parse(last_response.body)
    stored = SecureBidding::Project[response_body['id']]
    _(stored.state).must_equal 'published'
  end

  it 'HAPPY: returns bid count for project owner without bid payloads' do
    owner = create_account(username: 'count-owner', email: 'count-owner@example.com')
    bidder = create_account(username: 'count-bidder', email: 'count-bidder@example.com')

    post '/api/v1/projects',
         { title: 'count-project', budget_cents: 50_000, state: 'published' }.to_json,
         auth_header_for(owner)
    project_id = JSON.parse(last_response.body)['id']

    post '/api/v1/bid_submissions',
         { project_id: project_id, contractor_alias: 'bidder-a' }.merge(sample_client_bid_payload('secret')).to_json,
         auth_header_for(bidder)
    _(last_response.status).must_equal 201

    get "/api/v1/projects/#{project_id}/bid_count", '', auth_header_for(owner)
    _(last_response.status).must_equal 200
    body = JSON.parse(last_response.body)
    _(body['bid_count']).must_equal 1
  end

  it 'HAPPY: returns integrity snapshot after bidding deadline' do
    owner = create_account(username: 'snap-owner', email: 'snap-owner@example.com')
    bidder = create_account(username: 'snap-bidder', email: 'snap-bidder@example.com')

    post '/api/v1/projects',
         { title: 'snap-project', budget_cents: 50_000, state: 'published' }.to_json,
         auth_header_for(owner)
    project_id = JSON.parse(last_response.body)['id']

    post '/api/v1/bid_submissions',
         { project_id: project_id, contractor_alias: 'snap-bidder' }.merge(sample_client_bid_payload('secret')).to_json,
         auth_header_for(bidder)
    _(last_response.status).must_equal 201

    SecureBidding::Project[project_id].update(bidding_deadline: Time.now - 60)

    get "/api/v1/projects/#{project_id}/integrity_snapshot"
    _(last_response.status).must_equal 200
    body = JSON.parse(last_response.body)
    _(body['project_id']).must_equal project_id
    _(body['canonical_hash']).wont_be_nil
    _(body['snapshot_taken_at']).wont_be_nil
  end

  it 'SAD: returns 404 for integrity snapshot before bidding deadline' do
    project = SecureBidding::Project.create(
      title: 'pre-snap',
      budget_cents: 40_000,
      state: 'published',
      bidding_deadline: Time.now + 3600
    )

    get "/api/v1/projects/#{project.id}/integrity_snapshot"
    _(last_response.status).must_equal 404
    body = JSON.parse(last_response.body)
    _(body['error']).must_include 'not yet available'
  end

  it 'HAPPY: lists only published projects with GET /api/v1/projects' do
    SecureBidding::Project.create(title: 'p1', budget_cents: 10_000, state: 'saved')
    SecureBidding::Project.create(title: 'p2', budget_cents: 20_000, state: 'published')

    get '/api/v1/projects'

    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['projects']).must_be_kind_of Array
    _(response_body['projects'].length).must_equal 1
    _(response_body['projects'][0]['title']).must_equal 'p2'
  end

  it 'HAPPY: fetches a single project with GET /api/v1/projects/:id' do
    project = SecureBidding::Project.create(title: 'single-project', budget_cents: 50_000, state: 'published')

    get "/api/v1/projects/#{project.id}"

    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['id']).must_equal project.id
    _(response_body['title']).must_equal 'single-project'
    _(response_body['budget_cents']).must_equal 50_000
  end

  it 'SAD: returns 403 for saved project id on public project fetch' do
    project = SecureBidding::Project.create(title: 'saved-project', budget_cents: 50_000, state: 'saved')

    get "/api/v1/projects/#{project.id}"

    _(last_response.status).must_equal 403
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_include 'Forbidden'
  end

  it 'HAPPY: project owner can fetch their saved draft' do
    owner = create_account(username: 'draft-owner', email: 'draft-owner@example.com')

    post '/api/v1/projects',
         { title: 'my-draft', budget_cents: 40_000 }.to_json,
         auth_header_for(owner)
    _(last_response.status).must_equal 201
    project_id = JSON.parse(last_response.body)['id']

    get "/api/v1/projects/#{project_id}", '', auth_header_for(owner)

    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['title']).must_equal 'my-draft'
    _(response_body['state']).must_equal 'saved'
    _(response_body['policy']['show']).must_equal true
    _(response_body['policy']['update']).must_equal true
  end

  it 'HAPPY: unverified owner can view but not update their saved draft' do
    owner = create_account(username: 'unverified-draft-owner', email: 'unverified-draft-owner@example.com',
                           verified: false)

    post '/api/v1/projects',
         { title: 'blocked-create', budget_cents: 40_000 }.to_json,
         auth_header_for(owner)
    _(last_response.status).must_equal 403

    project = SecureBidding::Project.create(title: 'legacy-unverified-draft', budget_cents: 40_000, state: 'saved')
    role = SecureBidding::Role.ensure_role('project_owner')
    SecureBidding::ProjectMembership.create(
      account_id: owner.id,
      project_id: project.id,
      role_id: role.id
    )

    get "/api/v1/projects/#{project.id}", '', auth_header_for(owner)

    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['policy']['show']).must_equal true
    _(response_body['policy']['update']).must_equal false

    patch "/api/v1/projects/#{project.id}",
          { title: 'renamed' }.to_json,
          auth_header_for(owner)

    _(last_response.status).must_equal 403
  end

  it 'SAD: rejects invalid project payload' do
    account = create_account(username: 'creator3', email: 'creator3@example.com')
    
    post '/api/v1/projects', { title: '' }.to_json, auth_header_for(account)

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_be_kind_of Hash
  end

  it 'SAD: rejects non-numeric budget_cents' do
    account = create_account(username: 'creator4', email: 'creator4@example.com')
    
    post '/api/v1/projects',
         { title: 'bad-budget', budget_cents: 'not-a-number' }.to_json,
         auth_header_for(account)

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    error = response_body['error']
    message = error.is_a?(Hash) ? error.values.flatten.join(' ') : error.to_s
    _(message).must_match(/integer/i)
  end

  it 'SAD: rejects invalid project state value' do
    account = create_account(username: 'creator5', email: 'creator5@example.com')
    
    post '/api/v1/projects',
         { title: 'bad-state', budget_cents: 10_000, state: 'archived' }.to_json,
         auth_header_for(account)

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal "state must be 'saved' or 'published'"
  end

  it 'SAD: returns 404 for unknown project id' do
    get '/api/v1/projects/00000000-0000-0000-0000-000000000000'

    _(last_response.status).must_equal 404
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'Project not found'
  end

  it 'HAPPY: supports full cycle project -> bid submission -> project bid submissions list' do
    creator = create_account(username: 'flow-creator', email: 'flow-creator@example.com')
    bidder = create_account(username: 'flow-bidder', email: 'flow-bidder@example.com')
    post '/api/v1/projects',
         { title: 'flow-project', budget_cents: 99_000, state: 'published' }.to_json,
         auth_header_for(creator)
    _(last_response.status).must_equal 201
    project_id = JSON.parse(last_response.body)['id']

    post '/api/v1/bid_submissions',
         {
           project_id: project_id,
           contractor_alias: 'flow-freelancer'
         }.merge(sample_client_bid_payload('encrypted-like-payload')).to_json,
         auth_header_for(bidder)
    _(last_response.status).must_equal 201
    bid_submission_id = JSON.parse(last_response.body)['id']

    project = SecureBidding::Project[project_id]
    project.update(bidding_deadline: Time.now - 60)

    get "/api/v1/projects/#{project_id}/bid_submissions", '', auth_header_for(creator)
    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['project_id']).must_equal project_id
    _(response_body['bid_submissions']).must_be_kind_of Array
    _(response_body['bid_submissions'].length).must_equal 1
    _(response_body['bid_submissions'][0]['id']).must_equal bid_submission_id
    _(response_body['bid_submissions'][0]['contractor_alias']).must_equal 'flow-freelancer'
    _(response_body['bid_submissions'][0]['project_id']).must_equal project_id
  end

  it 'SECURITY: process_payment records the stored awarded amount and ignores client payment_amount_cents' do
    creator = create_account(username: 'fixed-pay-owner', email: 'fixed-pay-owner@example.com')
    bidder = create_account(username: 'fixed-pay-freelancer', email: 'fixed-pay-freelancer@example.com')

    post '/api/v1/projects',
         { title: 'fixed-pay-project', budget_cents: 99_000, state: 'published' }.to_json,
         auth_header_for(creator)
    project_id = JSON.parse(last_response.body)['id']

    post "/api/v1/projects/#{project_id}/bids",
         {
           bidder_account_id: bidder.id,
           contractor_alias: 'fixed-pay-freelancer'
         }.merge(sample_client_bid_payload('99000')).to_json,
         auth_header_for(bidder)
    bid_submission_id = JSON.parse(last_response.body)['id']

    project = SecureBidding::Project[project_id]
    project.update(bidding_deadline: Time.now - 60)

    post "/api/v1/projects/#{project_id}/award",
         { bid_submission_id: bid_submission_id, awarded_bid_amount_cents: 99_000 }.to_json,
         auth_header_for(creator)
    _(last_response.status).must_equal 200

    post "/api/v1/projects/#{project_id}/request_payment", {}.to_json, auth_header_for(bidder)
    _(last_response.status).must_equal 200

    post "/api/v1/projects/#{project_id}/process_payment",
         { payment_amount_cents: 1 }.to_json,
         auth_header_for(creator)

    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['payment_amount_cents']).must_equal 99_000
  end

  it 'HAPPY: awarded freelancer accepts payment and closes project' do
    creator = create_account(username: 'receipt-owner', email: 'receipt-owner@example.com')
    bidder = create_account(username: 'receipt-freelancer', email: 'receipt-freelancer@example.com')

    post '/api/v1/projects',
         { title: 'receipt-project', budget_cents: 99_000, state: 'published' }.to_json,
         auth_header_for(creator)
    project_id = JSON.parse(last_response.body)['id']

    post "/api/v1/projects/#{project_id}/bids",
         {
           bidder_account_id: bidder.id,
           contractor_alias: 'receipt-freelancer'
         }.merge(sample_client_bid_payload('99000')).to_json,
         auth_header_for(bidder)
    bid_submission_id = JSON.parse(last_response.body)['id']

    project = SecureBidding::Project[project_id]
    project.update(bidding_deadline: Time.now - 60)

    post "/api/v1/projects/#{project_id}/award",
         { bid_submission_id: bid_submission_id, awarded_bid_amount_cents: 99_000 }.to_json,
         auth_header_for(creator)
    _(last_response.status).must_equal 200

    post "/api/v1/projects/#{project_id}/request_payment", {}.to_json, auth_header_for(bidder)
    _(last_response.status).must_equal 200

    post "/api/v1/projects/#{project_id}/process_payment", {}.to_json, auth_header_for(creator)
    _(last_response.status).must_equal 200

    post "/api/v1/projects/#{project_id}/acknowledge_payment", {}.to_json, auth_header_for(creator)
    _(last_response.status).must_equal 403

    post "/api/v1/projects/#{project_id}/acknowledge_payment", {}.to_json, auth_header_for(bidder)
    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['state']).must_equal 'closed'
    _(response_body['payment_status']).must_equal 'acknowledged'
    _(response_body['payment_amount_cents']).must_equal 99_000
  end

  it 'SAD: rejects a non-UUID bidder_account_id when creating a project bid' do
    owner = create_account(username: 'bid-owner', email: 'bid-owner@example.com')

    post '/api/v1/projects',
         {
           title: 'uuid-bid-project',
           budget_cents: 99_000,
           state: 'published'
         }.to_json,
         auth_header_for(owner)
    _(last_response.status).must_equal 201
    project_id = JSON.parse(last_response.body)['id']

    post "/api/v1/projects/#{project_id}/bids",
         {
           bidder_account_id: 'not-a-uuid',
           contractor_alias: 'bad-bidder'
         }.merge(sample_client_bid_payload('should-fail')).to_json,
         auth_header_for(owner)

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'bidder_account_id must be a UUID'
  end

  it 'SAD: returns 404 for unknown project id on /api/v1/projects/:id/bid_submissions' do
    get '/api/v1/projects/00000000-0000-0000-0000-000000000000/bid_submissions'

    _(last_response.status).must_equal 404
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'Project not found'
  end

  it 'SAD: blocks mass assignment keys for project creation' do
    account = create_account(username: 'creator6', email: 'creator6@example.com')
    
    post '/api/v1/projects',
         { title: 'safe-project', budget_cents: 88_000, id: 'forced-id' }.to_json,
         auth_header_for(account)

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'Invalid project attributes'
    _(SecureBidding::Project.count).must_equal 0
  end

  it 'SAD: rejects SQL injection string in project id route' do
    get "/api/v1/projects/#{CGI.escape("00000000-0000-0000-0000-000000000000' OR 1=1 --")}"

    _(last_response.status).must_equal 404
  end


  it 'HAPPY: admin can update a project with PATCH /api/v1/projects/:id' do
    SecureBidding::AuthToken.setup(SecureBidding::AuthToken.generate_key)
    
    admin = create_account(username: 'admin-user', email: 'admin@example.com')
    admin.system_role = 'admin'
    admin.save

    project = SecureBidding::Project.create(title: 'original-project', budget_cents: 50_000, state: 'saved')

    headers = auth_header_for(admin)

    patch "/api/v1/projects/#{project.id}",
          { title: 'updated-project', budget_cents: 75_000 }.to_json,
          headers

    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['id']).must_equal project.id
    _(response_body['status']).must_equal 'updated'

    updated = SecureBidding::Project[project.id]
    _(updated.title).must_equal 'updated-project'
    _(updated.budget_cents).must_equal 75_000
  end

  it 'HAPPY: admin can delete a project with DELETE /api/v1/projects/:id' do
    SecureBidding::AuthToken.setup(SecureBidding::AuthToken.generate_key)
    
    admin = create_account(username: 'admin-user-delete', email: 'admin-delete@example.com')
    admin.system_role = 'admin'
    admin.save

    project = SecureBidding::Project.create(title: 'delete-project', budget_cents: 50_000, state: 'published')

    headers = auth_header_for(admin)

    delete "/api/v1/projects/#{project.id}", '', headers

    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['id']).must_equal project.id
    _(response_body['status']).must_equal 'deleted'
    _(SecureBidding::Project[project.id]).must_be_nil
  end

  it 'SAD: non-admin cannot update a project' do
    SecureBidding::AuthToken.setup(SecureBidding::AuthToken.generate_key)
    
    member = create_account(username: 'member-user', email: 'member@example.com')
    project = SecureBidding::Project.create(title: 'protected-project', budget_cents: 50_000, state: 'saved')

    headers = auth_header_for(member)

    patch "/api/v1/projects/#{project.id}",
          { title: 'hacked-project' }.to_json,
          headers

    _(last_response.status).must_equal 403
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).wont_be_nil
    
    _(SecureBidding::Project[project.id].title).must_equal 'protected-project'
  end

  it 'SAD: non-admin cannot delete a project' do
    SecureBidding::AuthToken.setup(SecureBidding::AuthToken.generate_key)
    
    member = create_account(username: 'member-user-delete', email: 'member-delete@example.com')
    project = SecureBidding::Project.create(title: 'protected-project-2', budget_cents: 50_000, state: 'published')

    headers = auth_header_for(member)

    delete "/api/v1/projects/#{project.id}", '', headers

    _(last_response.status).must_equal 403
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).wont_be_nil
    
    _(SecureBidding::Project[project.id]).wont_be_nil
  end

  it 'SAD: rejects project update with invalid state' do
    SecureBidding::AuthToken.setup(SecureBidding::AuthToken.generate_key)
    
    admin = create_account(username: 'admin-validate', email: 'admin-validate@example.com')
    admin.system_role = 'admin'
    admin.save

    project = SecureBidding::Project.create(title: 'validate-project', budget_cents: 50_000, state: 'saved')

    headers = auth_header_for(admin)

    patch "/api/v1/projects/#{project.id}",
          { state: 'archived' }.to_json,
          headers

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_include "state must be 'saved' or 'published'"
  end

  it 'SAD: rejects project update with invalid budget_cents' do
    SecureBidding::AuthToken.setup(SecureBidding::AuthToken.generate_key)
    
    admin = create_account(username: 'admin-budget', email: 'admin-budget@example.com')
    admin.system_role = 'admin'
    admin.save

    project = SecureBidding::Project.create(title: 'budget-project', budget_cents: 50_000, state: 'saved')

    headers = auth_header_for(admin)

    patch "/api/v1/projects/#{project.id}",
          { budget_cents: 'invalid' }.to_json,
          headers

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    error = response_body['error']
    message = error.is_a?(Hash) ? error.values.flatten.join(' ') : error.to_s
    _(message).must_match(/integer/i)
  end

  it 'HAPPY: owner-created co-owner request stays pending until collaborator accepts' do
    owner = create_account(username: 'owner-collab', email: 'owner-collab@example.com')
    co_owner = create_account(username: 'co-owner-collab', email: 'co-owner-collab@example.com')

    post '/api/v1/projects',
         { title: 'collab-project', budget_cents: 90_000 }.to_json,
         auth_header_for(owner)
    _(last_response.status).must_equal 201
    project_id = JSON.parse(last_response.body)['id']

    post "/api/v1/projects/#{project_id}/memberships",
         { account_id: co_owner.id, role: 'project_owner' }.to_json,
         auth_header_for(owner)

    _(last_response.status).must_equal 202
    request_body = JSON.parse(last_response.body)
    _(request_body['role']).must_equal 'project_owner'
    _(request_body['status']).must_equal 'pending'

    collaboration = SecureBidding::AccountProject.first(account_id: co_owner.id, project_id: project_id)
    _(collaboration).wont_be_nil
    _(collaboration.collaboration_role).must_equal 'pending_owner'

    pending_membership = SecureBidding::ProjectMembership.join(:roles, id: :role_id)
                                                        .where(
                                                          Sequel[:project_memberships][:account_id] => co_owner.id,
                                                          Sequel[:project_memberships][:project_id] => project_id,
                                                          Sequel[:roles][:name] => 'project_owner'
                                                        ).first
    _(pending_membership).must_be_nil

    patch "/api/v1/projects/#{project_id}",
          { title: 'collab-project-updated' }.to_json,
          auth_header_for(co_owner)
    _(last_response.status).must_equal 403

    post "/api/v1/projects/#{project_id}/memberships/accept", {}.to_json, auth_header_for(co_owner)
    _(last_response.status).must_equal 200

    accepted = SecureBidding::AccountProject.first(account_id: co_owner.id, project_id: project_id)
    _(accepted.collaboration_role).must_equal 'owner'

    patch "/api/v1/projects/#{project_id}",
          { title: 'collab-project-updated' }.to_json,
          auth_header_for(co_owner)
    _(last_response.status).must_equal 200
  end

  it 'HAPPY: admin can assign co-owner immediately without pending acceptance' do
    admin = create_account(username: 'collab-admin', email: 'collab-admin@example.com')
    admin.system_role = 'admin'
    admin.save
    owner = create_account(username: 'owner-direct-admin', email: 'owner-direct-admin@example.com')
    co_owner = create_account(username: 'co-owner-direct-admin', email: 'co-owner-direct-admin@example.com')

    post '/api/v1/projects',
         { title: 'admin-collab-project', budget_cents: 91_000 }.to_json,
         auth_header_for(owner)
    _(last_response.status).must_equal 201
    project_id = JSON.parse(last_response.body)['id']

    post "/api/v1/projects/#{project_id}/memberships",
         { account_id: co_owner.id, role: 'project_owner' }.to_json,
         auth_header_for(admin)

    _(last_response.status).must_equal 201
    membership_body = JSON.parse(last_response.body)
    _(membership_body['role']).must_equal 'project_owner'

    collaboration = SecureBidding::AccountProject.first(account_id: co_owner.id, project_id: project_id)
    _(collaboration).wont_be_nil
    _(collaboration.collaboration_role).must_equal 'owner'
  end

  it 'SAD: collaborator cannot accept ownership without pending request' do
    owner = create_account(username: 'owner-no-pending', email: 'owner-no-pending@example.com')
    other = create_account(username: 'other-no-pending', email: 'other-no-pending@example.com')

    post '/api/v1/projects',
         { title: 'no-pending-project', budget_cents: 92_000 }.to_json,
         auth_header_for(owner)
    _(last_response.status).must_equal 201
    project_id = JSON.parse(last_response.body)['id']

    post "/api/v1/projects/#{project_id}/memberships/accept", {}.to_json, auth_header_for(other)

    _(last_response.status).must_equal 404
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'No pending ownership request found'
  end

  it 'SAD: unverified member cannot create projects' do
    account = create_account(username: 'unverified-creator', email: 'unverified-creator@example.com', verified: false)

    post '/api/v1/projects',
         { title: 'blocked-project', budget_cents: 12_000 }.to_json,
         auth_header_for(account)

    _(last_response.status).must_equal 403
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'Forbidden: verify your email before creating projects'
  end

  it 'SAD: unverified member only sees published projects in list scope' do
    owner = create_account(username: 'verified-owner-scope', email: 'verified-owner-scope@example.com')
    unverified = create_account(username: 'unverified-scope', email: 'unverified-scope@example.com', verified: false)

    post '/api/v1/projects',
         { title: 'draft-only', budget_cents: 15_000 }.to_json,
         auth_header_for(owner)
    draft_id = JSON.parse(last_response.body)['id']

    SecureBidding::Project.create(title: 'public-listing', budget_cents: 18_000, state: 'published')

    get '/api/v1/projects', '', auth_header_for(unverified)

    _(last_response.status).must_equal 200
    titles = JSON.parse(last_response.body)['projects'].map { |p| p['title'] }
    _(titles).must_include 'public-listing'
    _(titles).wont_include 'draft-only'
    _(JSON.parse(last_response.body)['projects'].map { |p| p['id'] }).wont_include draft_id
  end

  it 'SAD: non-owner cannot add project memberships' do
    owner = create_account(username: 'owner-forbidden', email: 'owner-forbidden@example.com')
    outsider = create_account(username: 'outsider-forbidden', email: 'outsider-forbidden@example.com')
    target = create_account(username: 'target-forbidden', email: 'target-forbidden@example.com')

    post '/api/v1/projects',
         { title: 'locked-memberships', budget_cents: 95_000 }.to_json,
         auth_header_for(owner)
    _(last_response.status).must_equal 201
    project_id = JSON.parse(last_response.body)['id']

    post "/api/v1/projects/#{project_id}/memberships",
         { account_id: target.id, role: 'project_owner' }.to_json,
         auth_header_for(outsider)

    _(last_response.status).must_equal 403
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'Forbidden: only project owner or admin can manage project memberships'
  end
end
