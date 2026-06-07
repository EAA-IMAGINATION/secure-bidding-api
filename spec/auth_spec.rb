# frozen_string_literal: true

require_relative 'spec_helper'

# rubocop:disable Metrics/BlockLength
describe 'API /api/v1/auth/authenticate' do
  include Rack::Test::Methods

  def app
    SecureBidding::App.freeze.app
  end

  before do
    # Clean up database before each test
    SecureBidding::Database.migrate!
    SecureBidding::Account.dataset.delete
    SecureBidding::BidSubmission.dataset.delete
    SecureBidding::Project.dataset.delete
    
    # Create test account with password using service
    result = SecureBidding::Services::Accounts::CreateAccount.call(
      username: 'test_user',
      password: 'correct_password_123',
      email: 'test@example.com',
      phone: '+1234567890',
      system_role: 'member'
    )
    @account = result[:account]
  end

  describe 'HAPPY: POST /api/v1/auth/authenticate with valid credentials' do
    it 'returns 200 and authenticated user info' do
      signed_post '/api/v1/auth/authenticate',
           { username: 'test_user', password: 'correct_password_123' }

      _(last_response.status).must_equal 200

      response_body = JSON.parse(last_response.body)
      _(response_body['username']).must_equal 'test_user'
      _(response_body['id']).must_equal @account.id
      _(response_body['email']).must_equal 'test@example.com'
      _(response_body['system_role']).must_equal 'member'
      _(response_body).must_include 'system_roles'
      _(response_body).must_include 'token'
      _(response_body['token']).wont_be_nil
    end

    it 'returns account ID as UUID' do
      signed_post '/api/v1/auth/authenticate',
           { username: 'test_user', password: 'correct_password_123' }

      _(last_response.status).must_equal 200

      response_body = JSON.parse(last_response.body)
      _(response_body['id']).must_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end
  end

  describe 'SAD: POST /api/v1/auth/authenticate with invalid credentials' do
    it 'returns 401 for incorrect password' do
      signed_post '/api/v1/auth/authenticate',
           { username: 'test_user', password: 'wrong_password' }

      _(last_response.status).must_equal 401

      response_body = JSON.parse(last_response.body)
      _(response_body).must_include 'error'
      _(response_body['error']).must_equal 'Invalid credentials'
    end

    it 'returns 401 for non-existent user' do
      signed_post '/api/v1/auth/authenticate',
           { username: 'nonexistent_user', password: 'any_password' }

      _(last_response.status).must_equal 401

      response_body = JSON.parse(last_response.body)
      _(response_body).must_include 'error'
      _(response_body['error']).must_equal 'Invalid credentials'
    end

    it 'returns 400 for empty password' do
      signed_post '/api/v1/auth/authenticate',
           { username: 'test_user', password: '' }

      _(last_response.status).must_equal 400
    end

    it 'returns 400 for missing credentials' do
      signed_post '/api/v1/auth/authenticate',
           {}

      _(last_response.status).must_equal 400
    end
  end

  describe 'SAD: unsigned requests' do
    it 'returns 403 when request is not signed' do
      post '/api/v1/auth/authenticate',
           JSON.generate({ username: 'test_user', password: 'correct_password_123' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 403
      response_body = JSON.parse(last_response.body)
      _(response_body['error']).must_equal 'Must sign request'
    end
  end

  describe 'SAD: POST /api/v1/auth/authenticate with invalid JSON' do
    it 'returns 500 for malformed JSON (JSON parsing error)' do
      post '/api/v1/auth/authenticate',
           'not valid json',
           'CONTENT_TYPE' => 'application/json'

      # JSON parsing errors result in 500 due to error handler
      _(last_response.status).must_equal 500
    end
  end
end
# rubocop:enable Metrics/BlockLength
