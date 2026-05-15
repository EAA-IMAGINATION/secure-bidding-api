# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'  # Use test mode which allows HTTP

require 'minitest/autorun'
require 'rack/test'
require 'json'
require_relative '../app/require_app'

# rubocop:disable Metrics/BlockLength
describe 'API SSL/TLS Enforcement' do
  include Rack::Test::Methods

  def app
    SecureBidding::App.freeze.app
  end

  before do
    # Clean up database before each test
    SecureBidding::Database.migrate!
    SecureBidding::Account.dataset.delete
  end

  describe 'HAPPY: HTTP requests allowed in test mode' do
    it 'allows HTTP requests to proceed in test/development' do
      get '/'

      # Should not be blocked by SSL check in test mode
      _(last_response.status).must_equal 200

      response_body = JSON.parse(last_response.body)
      _(response_body['status']).must_equal 'ok'
    end
  end

  describe 'Unit tests for HttpRequest security check' do
    it 'HttpRequest secure? returns true in test mode' do
      # Create a mock Roda routing object with HTTP scheme
      mock_routing = Minitest::Mock.new
      mock_routing.expect(:scheme, 'http')

      http_req = SecureBidding::HttpRequest.new(mock_routing)
      # In test mode, secure? should return true even with http scheme
      _(http_req.secure?).must_equal true
    end

    it 'HttpRequest secure? returns true for HTTPS scheme in any mode' do
      mock_routing = Minitest::Mock.new
      mock_routing.expect(:scheme, 'https')

      http_req = SecureBidding::HttpRequest.new(mock_routing)
      # HTTPS should always be considered secure
      _(http_req.secure?).must_equal true
    end
  end

  describe 'Authentication endpoint' do
    it 'allows POST /api/v1/auth/authenticate in test mode' do
      result = SecureBidding::Services::Accounts::CreateAccount.call(
        username: 'auth_test_user',
        password: 'test_password_123',
        email: 'authtest@example.com',
        phone: '+1234567890',
        system_role: 'member'
      )

      post '/api/v1/auth/authenticate',
           JSON.generate({ username: 'auth_test_user', password: 'test_password_123' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
    end
  end
end
# rubocop:enable Metrics/BlockLength
