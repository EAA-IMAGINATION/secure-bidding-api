# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'json'
require 'base64'
require_relative '../app/require_app'

# rubocop:disable Metrics/BlockLength
describe 'API /api/v1/bids' do
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

  def create_project_for(account, title: 'legacy-bid-project')
    post '/api/v1/projects',
         { title: title, budget_cents: 10_000 }.to_json,
         auth_header_for(account)

    JSON.parse(last_response.body)['id']
  end

  def valid_bid_payload(project_id)
    {
      contractor: 'XYZ Construction',
      project_id: project_id,
      encrypted_bid: Base64.strict_encode64('encrypted_secure_bid_data')
    }
  end

  before do
    SecureBidding::AuthToken.setup(SecureBidding::AuthToken.generate_key)
    SecureBidding::Database.migrate!
    SecureBidding::BidSubmission.dataset.delete
    SecureBidding::ProjectMembership.dataset.delete if SecureBidding::Database.db.table_exists?(:project_memberships)
    SecureBidding::Project.dataset.delete
    SecureBidding::Account.dataset.delete
    Dir.glob('app/db/store/*.json').each { |f| File.delete(f) }
  end

  describe 'HAPPY: Root route' do
    it 'returns health check message' do
      get '/'

      _(last_response.status).must_equal 200

      response_body = JSON.parse(last_response.body)
      _(response_body['status']).must_equal 'ok'
      _(response_body['message']).must_include 'Secure Bidding API'
    end

    it 'does not require DATABASE_URL environment variable' do
      ENV.delete('DATABASE_URL')

      get '/'

      _(last_response.status).must_equal 200
      _(ENV['DATABASE_URL']).must_be_nil
    end
  end

  describe 'HAPPY: POST /api/v1/bids with valid data' do
    it 'returns 201 and creates the bid when caller manages the project' do
      owner = create_account(username: 'bid-owner', email: 'bid-owner@example.com')
      project_id = create_project_for(owner)

      post '/api/v1/bids', valid_bid_payload(project_id).to_json, auth_header_for(owner)

      _(last_response.status).must_equal 201

      response_body = JSON.parse(last_response.body)
      _(response_body['bid_id']).wont_be_nil
      _(response_body['bid_id']).must_match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
      _(response_body['status']).must_equal 'created'

      files = Dir.glob('app/db/store/*.json')
      _(files.length).must_equal 1

      raw_storage = File.read(files.first)
      _(raw_storage).wont_include 'XYZ Construction'
      _(raw_storage).wont_include project_id

      saved_bid = SecureBidding::Bid.find(response_body['bid_id'])
      _(saved_bid.contractor).must_equal 'XYZ Construction'
      _(saved_bid.project_id).must_equal project_id
    end
  end

  describe 'HAPPY: GET /api/v1/bids/:id' do
    it 'returns bid details for authorized project manager' do
      owner = create_account(username: 'show-owner', email: 'show-owner@example.com')
      project_id = create_project_for(owner)

      bid = SecureBidding::Bid.new(
        contractor: 'Acme Corp',
        project_id: project_id,
        encrypted_bid: Base64.strict_encode64('secret_encrypted_data')
      )
      bid.save

      get "/api/v1/bids/#{bid.id}", nil, auth_header_for(owner)

      _(last_response.status).must_equal 200

      response_body = JSON.parse(last_response.body)
      _(response_body['id']).must_equal bid.id
      _(response_body['contractor']).must_equal 'Acme Corp'
      _(response_body['project_id']).must_equal project_id
    end
  end

  describe 'HAPPY: GET /api/v1/bids' do
    it 'returns bid IDs for managed projects' do
      owner = create_account(username: 'list-owner', email: 'list-owner@example.com')
      project_id = create_project_for(owner)

      bid1 = SecureBidding::Bid.new(
        contractor: 'Corp A',
        project_id: project_id,
        encrypted_bid: Base64.strict_encode64('data1')
      )
      bid1.save

      other_project_id = create_project_for(owner, title: 'other-project')
      bid2 = SecureBidding::Bid.new(
        contractor: 'Corp B',
        project_id: other_project_id,
        encrypted_bid: Base64.strict_encode64('data2')
      )
      bid2.save

      get '/api/v1/bids', nil, auth_header_for(owner)

      _(last_response.status).must_equal 200

      response_body = JSON.parse(last_response.body)
      _(response_body['bid_ids']).must_include bid1.id
      _(response_body['bid_ids']).must_include bid2.id
    end

    it 'returns empty array when no bids exist' do
      owner = create_account(username: 'empty-owner', email: 'empty-owner@example.com')
      create_project_for(owner)

      get '/api/v1/bids', nil, auth_header_for(owner)

      _(last_response.status).must_equal 200

      response_body = JSON.parse(last_response.body)
      _(response_body['bid_ids']).must_be_empty
    end
  end

  describe 'SAD: authentication and authorization' do
    it 'returns 401 when creating a bid without a token' do
      owner = create_account(username: 'no-auth-owner', email: 'no-auth-owner@example.com')
      project_id = create_project_for(owner)

      post '/api/v1/bids',
           valid_bid_payload(project_id).to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      _(last_response.status).must_equal 401
      _(Dir.glob('app/db/store/*.json')).must_be_empty
    end

    it 'returns 403 when a non-manager creates a legacy bid' do
      owner = create_account(username: 'real-owner', email: 'real-owner@example.com')
      outsider = create_account(username: 'outsider', email: 'outsider@example.com')
      project_id = create_project_for(owner)

      post '/api/v1/bids', valid_bid_payload(project_id).to_json, auth_header_for(outsider)

      _(last_response.status).must_equal 403
      _(Dir.glob('app/db/store/*.json')).must_be_empty
    end

    it 'returns 401 when listing bids without a token' do
      get '/api/v1/bids'

      _(last_response.status).must_equal 401
    end

    it 'returns 404 when showing a bid to an unauthorized account' do
      owner = create_account(username: 'hide-owner', email: 'hide-owner@example.com')
      outsider = create_account(username: 'hide-outsider', email: 'hide-outsider@example.com')
      project_id = create_project_for(owner)

      bid = SecureBidding::Bid.new(
        contractor: 'Hidden Corp',
        project_id: project_id,
        encrypted_bid: Base64.strict_encode64('hidden')
      )
      bid.save

      get "/api/v1/bids/#{bid.id}", nil, auth_header_for(outsider)

      _(last_response.status).must_equal 404
    end
  end

  describe 'SAD: POST /api/v1/bids with invalid data' do
    it 'returns 400 when encrypted_bid is missing' do
      owner = create_account(username: 'missing-owner', email: 'missing-owner@example.com')
      project_id = create_project_for(owner)

      post '/api/v1/bids',
           { contractor: 'ABC Corp', project_id: project_id }.to_json,
           auth_header_for(owner)

      _(last_response.status).must_equal 400
      _(Dir.glob('app/db/store/*.json')).must_be_empty
    end

    it 'returns 400 when project_id is not a UUID' do
      owner = create_account(username: 'uuid-owner', email: 'uuid-owner@example.com')
      create_project_for(owner)

      payload = valid_bid_payload('project-123')
      post '/api/v1/bids', payload.to_json, auth_header_for(owner)

      _(last_response.status).must_equal 400
      _(Dir.glob('app/db/store/*.json')).must_be_empty
    end

    it 'returns 400 when encrypted_bid is not valid base64' do
      owner = create_account(username: 'b64-owner', email: 'b64-owner@example.com')
      project_id = create_project_for(owner)

      payload = valid_bid_payload(project_id).merge(encrypted_bid: 'not!!!base64')
      post '/api/v1/bids', payload.to_json, auth_header_for(owner)

      _(last_response.status).must_equal 400
      _(Dir.glob('app/db/store/*.json')).must_be_empty
    end
  end

  describe 'SAD: GET /api/v1/bids/:id with non-existent ID' do
    it 'returns 404 for non-existent bid' do
      owner = create_account(username: 'nf-owner', email: 'nf-owner@example.com')
      create_project_for(owner)

      get '/api/v1/bids/00000000-0000-4000-8000-000000000000', nil, auth_header_for(owner)

      _(last_response.status).must_equal 404

      response_body = JSON.parse(last_response.body)
      _(response_body['error']).must_equal 'Bid not found'
    end

    it 'returns 404 for path traversal style id' do
      owner = create_account(username: 'traversal-owner', email: 'traversal-owner@example.com')
      create_project_for(owner)

      get '/api/v1/bids/../../../etc/passwd', nil, auth_header_for(owner)

      _(last_response.status).must_equal 404
    end
  end
end
# rubocop:enable Metrics/BlockLength
