# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'json'
require_relative '../app/require_app'

# rubocop:disable Metrics/BlockLength
describe 'API /api/v1/bids' do
  include Rack::Test::Methods

  def app
    SecureBidding::App.freeze.app
  end

  before do
    # Clean up store before each test
    SecureBidding::Database.migrate!
    SecureBidding::Secret.dataset.delete
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
    it 'returns 201 and creates the bid' do
      bid_data = {
        contractor: 'XYZ Construction',
        project_id: 'project-456',
        encrypted_bid: 'encrypted_secure_bid_data_base64=='
      }

      post '/api/v1/bids', bid_data.to_json, { 'CONTENT_TYPE' => 'application/json' }

      # Verify 201 status
      _(last_response.status).must_equal 201

      # Verify response structure
      response_body = JSON.parse(last_response.body)
      _(response_body['bid_id']).wont_be_nil
      _(response_body['bid_id']).must_match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
      _(response_body['status']).must_equal 'created'

      # Verify the bid was actually saved to storage
      files = Dir.glob('app/db/store/*.json')
      _(files.length).must_equal 1

      # Verify saved data integrity
      saved_data = JSON.parse(File.read(files.first))
      _(saved_data['id']).must_equal response_body['bid_id']
      _(saved_data['contractor']).must_equal 'XYZ Construction'
      _(saved_data['project_id']).must_equal 'project-456'
      _(saved_data['encrypted_bid']).must_equal 'encrypted_secure_bid_data_base64=='
    end
  end

  describe 'HAPPY: GET /api/v1/bids/:id.json' do
    it 'returns bid details for valid id' do
      # Create a bid first
      bid = SecureBidding::Bid.new(
        contractor: 'Acme Corp',
        project_id: 'project-789',
        encrypted_bid: 'secret_encrypted_data'
      )
      bid.save

      # Get the bid
      get "/api/v1/bids/#{bid.id}"

      _(last_response.status).must_equal 200

      response_body = JSON.parse(last_response.body)
      _(response_body['id']).must_equal bid.id
      _(response_body['contractor']).must_equal 'Acme Corp'
      _(response_body['project_id']).must_equal 'project-789'
      _(response_body['encrypted_bid']).must_equal 'secret_encrypted_data'
    end
  end

  describe 'HAPPY: GET /api/v1/bids' do
    it 'returns all bid IDs' do
      # Create multiple bids
      bid1 = SecureBidding::Bid.new(
        contractor: 'Corp A',
        project_id: 'proj-1',
        encrypted_bid: 'data1'
      )
      bid1.save

      bid2 = SecureBidding::Bid.new(
        contractor: 'Corp B',
        project_id: 'proj-2',
        encrypted_bid: 'data2'
      )
      bid2.save

      # Get all bids
      get '/api/v1/bids'

      _(last_response.status).must_equal 200

      response_body = JSON.parse(last_response.body)
      _(response_body['bid_ids']).must_be_kind_of Array
      _(response_body['bid_ids'].length).must_equal 2
      _(response_body['bid_ids']).must_include bid1.id
      _(response_body['bid_ids']).must_include bid2.id
    end

    it 'returns empty array when no bids exist' do
      get '/api/v1/bids'

      _(last_response.status).must_equal 200

      response_body = JSON.parse(last_response.body)
      _(response_body['bid_ids']).must_be_kind_of Array
      _(response_body['bid_ids']).must_be_empty
    end
  end

  describe 'SAD: POST /api/v1/bids with missing data' do
    it 'returns 400 when encrypted_bid is missing' do
      bid_data = {
        contractor: 'ABC Corp',
        project_id: 'project-123'
        # encrypted_bid is intentionally missing
      }

      post '/api/v1/bids', bid_data.to_json, { 'CONTENT_TYPE' => 'application/json' }

      # Verify 400 status
      _(last_response.status).must_equal 400

      # Verify no bid was saved
      files = Dir.glob('app/db/store/*.json')
      _(files.length).must_equal 0
    end

    it 'returns 400 when encrypted_bid is empty string' do
      bid_data = {
        contractor: 'ABC Corp',
        project_id: 'project-123',
        encrypted_bid: ''
      }

      post '/api/v1/bids', bid_data.to_json, { 'CONTENT_TYPE' => 'application/json' }

      # Verify 400 status
      _(last_response.status).must_equal 400

      # Verify no bid was saved
      files = Dir.glob('app/db/store/*.json')
      _(files.length).must_equal 0
    end

    it 'returns 400 when encrypted_bid is only whitespace' do
      bid_data = {
        contractor: 'ABC Corp',
        project_id: 'project-123',
        encrypted_bid: '   '
      }

      post '/api/v1/bids', bid_data.to_json, { 'CONTENT_TYPE' => 'application/json' }

      # Verify 400 status
      _(last_response.status).must_equal 400

      # Verify no bid was saved
      files = Dir.glob('app/db/store/*.json')
      _(files.length).must_equal 0
    end
  end

  describe 'SAD: GET /api/v1/bids/:id.json with non-existent ID' do
    it 'returns 404 for non-existent bid' do
      get '/api/v1/bids/non-existent-id-12345'

      _(last_response.status).must_equal 404

      response_body = JSON.parse(last_response.body)
      _(response_body['error']).must_equal 'Bid not found'
    end
  end
end
# rubocop:enable Metrics/BlockLength
