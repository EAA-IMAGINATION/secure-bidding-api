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
    post '/api/v1/projects',
         { title: 'demo-project', budget_cents: 25_000 }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 201
    response_body = JSON.parse(last_response.body)
    _(response_body['id']).wont_be_nil
    _(response_body['status']).must_equal 'created'
    stored = SecureBidding::Project[response_body['id']]
    _(stored.state).must_equal 'saved'
  end

  it 'HAPPY: creates a published project when state=published is provided' do
    post '/api/v1/projects',
         { title: 'published-project', budget_cents: 33_000, state: 'published' }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }

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
    post '/api/v1/projects', { title: '' }.to_json, { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'title and budget_cents are required'
  end

  it 'SAD: rejects non-numeric budget_cents' do
    post '/api/v1/projects',
         { title: 'bad-budget', budget_cents: 'not-a-number' }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'budget_cents must be a non-negative integer'
  end

  it 'SAD: rejects invalid project state value' do
    post '/api/v1/projects',
         { title: 'bad-state', budget_cents: 10_000, state: 'archived' }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }

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
    bidder = create_account(username: 'flow-bidder', email: 'flow-bidder@example.com')
    post '/api/v1/projects',
         { title: 'flow-project', budget_cents: 99_000, state: 'published' }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }
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
    post '/api/v1/projects',
         { title: 'safe-project', budget_cents: 88_000, id: 'forced-id' }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'Invalid project attributes'
    _(SecureBidding::Project.count).must_equal 0
  end

  it 'SAD: rejects SQL injection string in project id route' do
    get "/api/v1/projects/#{CGI.escape("00000000-0000-0000-0000-000000000000' OR 1=1 --")}"

    _(last_response.status).must_equal 404
  end
end
