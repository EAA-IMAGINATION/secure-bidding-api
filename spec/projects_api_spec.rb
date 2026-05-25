# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'json'
require 'cgi'
require_relative '../app/require_app'

describe 'API /api/v1/projects' do
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

  it 'SAD: returns 404 for saved project id on public project fetch' do
    project = SecureBidding::Project.create(title: 'saved-project', budget_cents: 50_000, state: 'saved')

    get "/api/v1/projects/#{project.id}"

    _(last_response.status).must_equal 404
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'Project not found'
  end

  it 'SAD: rejects invalid project payload' do
    account = create_account(username: 'creator3', email: 'creator3@example.com')
    
    post '/api/v1/projects', { title: '' }.to_json, auth_header_for(account)

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'title and budget_cents are required'
  end

  it 'SAD: rejects non-numeric budget_cents' do
    account = create_account(username: 'creator4', email: 'creator4@example.com')
    
    post '/api/v1/projects',
         { title: 'bad-budget', budget_cents: 'not-a-number' }.to_json,
         auth_header_for(account)

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'budget_cents must be a non-negative integer'
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
           contractor_alias: 'flow-freelancer',
           plaintext_bid: 'encrypted-like-payload'
         }.to_json,
         auth_header_for(bidder)
    _(last_response.status).must_equal 201
    bid_submission_id = JSON.parse(last_response.body)['id']

    get "/api/v1/projects/#{project_id}/bid_submissions"
    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['project_id']).must_equal project_id
    _(response_body['bid_submissions']).must_be_kind_of Array
    _(response_body['bid_submissions'].length).must_equal 1
    _(response_body['bid_submissions'][0]['id']).must_equal bid_submission_id
    _(response_body['bid_submissions'][0]['contractor_alias']).must_equal 'flow-freelancer'
    _(response_body['bid_submissions'][0]['project_id']).must_equal project_id
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
    _(response_body['error']).must_include 'budget_cents must be a non-negative integer'
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
