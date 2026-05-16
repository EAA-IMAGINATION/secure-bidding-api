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

  describe 'SAD: HTTP requests blocked in production' do
    it 'returns JSON 403 for insecure production requests' do
      original_env = ENV['RACK_ENV']
      ENV['RACK_ENV'] = 'production'

      get '/'

      _(last_response.status).must_equal 403

      response_body = JSON.parse(last_response.body)
      _(response_body['message']).must_equal 'TLS/SSL Required'
    ensure
      ENV['RACK_ENV'] = original_env
    end
  end

  describe 'Unit tests for HttpRequest security check' do
    it 'HttpRequest secure? returns true in test mode' do
      # Create a mock Roda routing object with HTTP scheme
      mock_routing = Object.new
      def mock_routing.scheme
        'http'
      end

      http_req = SecureBidding::HttpRequest.new(mock_routing)
      # In test mode, secure? should return true even with http scheme
      _(http_req.secure?).must_equal true
    end

    it 'HttpRequest secure? returns true for HTTPS scheme in any mode' do
      mock_routing = Object.new
      def mock_routing.scheme
        'https'
      end

      http_req = SecureBidding::HttpRequest.new(mock_routing)
      # HTTPS should always be considered secure
      _(http_req.secure?).must_equal true
    end
  end

  describe 'authenticated_account method (Bearer token parsing)' do
    let(:payload_data) { { user_id: '123', username: 'testuser', role: 'member' } }

    let(:payload_data) { { user_id: '123', username: 'testuser', role: 'member' } }

    it 'returns nil when Authorization header is absent' do
      mock_routing = Object.new
      def mock_routing.env
        {}
      end

      http_req = SecureBidding::HttpRequest.new(mock_routing)
      _(http_req.authenticated_account).must_be_nil
    end

    it 'returns nil when Authorization header is empty' do
      mock_routing = Object.new
      def mock_routing.env
        { 'HTTP_AUTHORIZATION' => nil }
      end

      http_req = SecureBidding::HttpRequest.new(mock_routing)
      _(http_req.authenticated_account).must_be_nil
    end

    it 'returns nil when Authorization header has no space separator' do
      mock_routing = Object.new
      def mock_routing.env
        { 'HTTP_AUTHORIZATION' => 'InvalidFormat' }
      end

      http_req = SecureBidding::HttpRequest.new(mock_routing)
      _(http_req.authenticated_account).must_be_nil
    end

    it 'returns nil when Authorization scheme is not Bearer' do
      mock_routing = Object.new
      def mock_routing.env
        { 'HTTP_AUTHORIZATION' => 'Basic sometoken' }
      end

      http_req = SecureBidding::HttpRequest.new(mock_routing)
      _(http_req.authenticated_account).must_be_nil
    end

    it 'returns payload with valid Bearer token' do
      # Create a valid token
      SecureBidding::AuthToken.setup(SecureBidding::AuthToken.generate_key)
      token = SecureBidding::AuthToken.tokenize(payload_data)

      mock_routing = Object.new
      env = { 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
      define_method_on_object(mock_routing, :env, env)

      http_req = SecureBidding::HttpRequest.new(mock_routing)
      payload = http_req.authenticated_account

      _(payload[:user_id]).must_equal '123'
      _(payload[:username]).must_equal 'testuser'
      _(payload[:role]).must_equal 'member'
    end

    it 'handles case-insensitive Bearer scheme (bearer)' do
      SecureBidding::AuthToken.setup(SecureBidding::AuthToken.generate_key)
      token = SecureBidding::AuthToken.tokenize(payload_data)

      mock_routing = Object.new
      env = { 'HTTP_AUTHORIZATION' => "bearer #{token}" }
      define_method_on_object(mock_routing, :env, env)

      http_req = SecureBidding::HttpRequest.new(mock_routing)
      payload = http_req.authenticated_account

      _(payload[:user_id]).must_equal '123'
    end

    it 'handles case-insensitive Bearer scheme (BEARER)' do
      SecureBidding::AuthToken.setup(SecureBidding::AuthToken.generate_key)
      token = SecureBidding::AuthToken.tokenize(payload_data)

      mock_routing = Object.new
      env = { 'HTTP_AUTHORIZATION' => "BEARER #{token}" }
      define_method_on_object(mock_routing, :env, env)

      http_req = SecureBidding::HttpRequest.new(mock_routing)
      payload = http_req.authenticated_account

      _(payload[:user_id]).must_equal '123'
    end

    it 'raises InvalidTokenError for malformed token' do
      mock_routing = Object.new
      def mock_routing.env
        { 'HTTP_AUTHORIZATION' => 'Bearer invalidtoken123' }
      end

      http_req = SecureBidding::HttpRequest.new(mock_routing)

      _(proc { http_req.authenticated_account }).must_raise SecureBidding::InvalidTokenError
    end

    it 'raises ExpiredTokenError for expired token' do
      SecureBidding::AuthToken.setup(SecureBidding::AuthToken.generate_key)
      # Create a token that expires in -1 second (already expired)
      token = SecureBidding::AuthToken.tokenize(payload_data, -1)

      mock_routing = Object.new
      env = { 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
      define_method_on_object(mock_routing, :env, env)

      http_req = SecureBidding::HttpRequest.new(mock_routing)

      _(proc { http_req.authenticated_account }).must_raise SecureBidding::ExpiredTokenError
    end

    private

    def define_method_on_object(obj, method_name, return_value)
      obj.define_singleton_method(method_name) { return_value }
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
