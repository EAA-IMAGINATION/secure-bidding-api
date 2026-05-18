# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'json'
require 'webmock/minitest'
require_relative '../app/require_app'

# rubocop:disable Metrics/BlockLength
describe 'API /api/v1/auth registration endpoints' do
  include Rack::Test::Methods

  def app
    SecureBidding::App.freeze.app
  end

  before do
    SecureBidding::Database.migrate!
    SecureBidding::BidSubmission.dataset.delete
    SecureBidding::Project.dataset.delete
    SecureBidding::AccountProject.dataset.delete
    SecureBidding::Account.dataset.delete
    SecureBidding::AuthToken.setup(SecureBidding::AuthToken.generate_key)
    WebMock.reset!
  end

  # POST /api/v1/auth/availability tests
  describe 'POST /api/v1/auth/availability' do
    it 'HAPPY: returns available true for new username and email' do
      post '/api/v1/auth/availability',
           JSON.generate({ username: 'newuser', email: 'new@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
      response_body = JSON.parse(last_response.body)
      _(response_body['available']).must_be_kind_of Hash
      _(response_body['available']['username']).must_equal true
      _(response_body['available']['email']).must_equal true
    end

    it 'HAPPY: returns available false for existing username' do
      account = SecureBidding::Account.new(username: 'existing_user', system_role: 'member')
      account.set_password('testpass123')
      account.set_email('existing@example.com')
      account.save

      post '/api/v1/auth/availability',
           JSON.generate({ username: 'existing_user', email: 'different@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
      response_body = JSON.parse(last_response.body)
      _(response_body['available']['username']).must_equal false
      _(response_body['available']['email']).must_equal true
    end

    it 'HAPPY: returns available false for existing email' do
      account = SecureBidding::Account.new(username: 'existing_user2', system_role: 'member')
      account.set_password('testpass123')
      account.set_email('taken@example.com')
      account.save

      post '/api/v1/auth/availability',
           JSON.generate({ username: 'different_user', email: 'taken@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
      response_body = JSON.parse(last_response.body)
      _(response_body['available']['username']).must_equal true
      _(response_body['available']['email']).must_equal false
    end

    it 'HAPPY: handles empty username gracefully' do
      post '/api/v1/auth/availability',
           JSON.generate({ username: '', email: 'test@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
    end

    it 'HAPPY: handles empty email gracefully' do
      post '/api/v1/auth/availability',
           JSON.generate({ username: 'testuser', email: '' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
    end
  end

  # POST /api/v1/auth/register tests
  describe 'POST /api/v1/auth/register' do
    it 'HAPPY: creates unverified account and sends verification email' do
      stub_request(:post, 'https://send.api.mailtrap.io/api/send')
        .to_return(status: 200, body: JSON.generate({ ok: true }))

      post '/api/v1/auth/register',
           JSON.generate({ username: 'newregister', email: 'register@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
      response_body = JSON.parse(last_response.body)
      _(response_body['message']).must_include 'Check your email'
      _(response_body['account_id']).wont_be_nil

      stored = SecureBidding::Account[response_body['account_id']]
      _(stored).wont_be_nil
      _(stored.username).must_equal 'newregister'
      _(stored.email).must_equal 'register@example.com'
      _(stored.email_verified_at).must_be_nil
      _(stored.registration_token).wont_be_nil
    end

    it 'HAPPY: email is encrypted in database' do
      stub_request(:post, 'https://send.api.mailtrap.io/api/send')
        .to_return(status: 200, body: JSON.generate({ ok: true }))

      post '/api/v1/auth/register',
           JSON.generate({ username: 'encrypted_user', email: 'encrypted@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      response_body = JSON.parse(last_response.body)
      stored = SecureBidding::Account[response_body['account_id']]
      
      _(stored.email_secure).wont_equal 'encrypted@example.com'
      _(stored.email).must_equal 'encrypted@example.com'
    end

    it 'SAD: returns 400 for missing username' do
      stub_request(:post, 'https://send.api.mailtrap.io/api/send')
        .to_return(status: 200, body: JSON.generate({ ok: true }))

      post '/api/v1/auth/register',
           JSON.generate({ email: 'test@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 400
      response_body = JSON.parse(last_response.body)
      _(response_body['error']).must_include 'required'
    end

    it 'SAD: returns 400 for missing email' do
      stub_request(:post, 'https://send.api.mailtrap.io/api/send')
        .to_return(status: 200, body: JSON.generate({ ok: true }))

      post '/api/v1/auth/register',
           JSON.generate({ username: 'testuser' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 400
      response_body = JSON.parse(last_response.body)
      _(response_body['error']).must_include 'required'
    end

    it 'SAD: returns 422 for taken username' do
      account = SecureBidding::Account.new(username: 'taken_user', system_role: 'member')
      account.set_password('testpass123')
      account.set_email('taken@example.com')
      account.save

      stub_request(:post, 'https://send.api.mailtrap.io/api/send')
        .to_return(status: 200, body: JSON.generate({ ok: true }))

      post '/api/v1/auth/register',
           JSON.generate({ username: 'taken_user', email: 'newuser@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 422
      response_body = JSON.parse(last_response.body)
      _(response_body['error']).must_include 'username'
    end

    it 'SAD: returns 422 for taken email' do
      account = SecureBidding::Account.new(username: 'existing', system_role: 'member')
      account.set_password('testpass123')
      account.set_email('taken@example.com')
      account.save

      stub_request(:post, 'https://send.api.mailtrap.io/api/send')
        .to_return(status: 200, body: JSON.generate({ ok: true }))

      post '/api/v1/auth/register',
           JSON.generate({ username: 'newuser', email: 'taken@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 422
      response_body = JSON.parse(last_response.body)
      _(response_body['error']).must_include 'email'
    end

    it 'SAD: returns 500 if email service fails' do
      stub_request(:post, 'https://send.api.mailtrap.io/api/send')
        .to_return(status: 500, body: 'Internal Server Error')

      post '/api/v1/auth/register',
           JSON.generate({ username: 'mailuser', email: 'mail@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 500
      response_body = JSON.parse(last_response.body)
      _(response_body['error']).must_include 'email'
    end

    it 'SAD: deletes account if email service fails' do
      stub_request(:post, 'https://send.api.mailtrap.io/api/send')
        .to_return(status: 500, body: 'Internal Server Error')

      post '/api/v1/auth/register',
           JSON.generate({ username: 'failmail', email: 'failmail@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 500

      # Verify account was deleted (not in database)
      account = SecureBidding::Account.where(username: 'failmail').first
      _(account).must_be_nil

      # Verify user can retry registration after email failure
      stub_request(:post, 'https://send.api.mailtrap.io/api/send')
        .to_return(status: 200, body: JSON.generate({ ok: true }))

      post '/api/v1/auth/register',
           JSON.generate({ username: 'failmail', email: 'failmail@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
      response_body = JSON.parse(last_response.body)
      _(response_body['account_id']).wont_be_nil
    end
  end

  # POST /api/v1/auth/verify tests
  describe 'POST /api/v1/auth/verify' do
    it 'HAPPY: verifies account and returns session token' do
      stub_request(:post, 'https://send.api.mailtrap.io/api/send')
        .to_return(status: 200, body: JSON.generate({ ok: true }))

      post '/api/v1/auth/register',
           JSON.generate({ username: 'verifyuser', email: 'verify@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      register_response = JSON.parse(last_response.body)
      account_id = register_response['account_id']
      account = SecureBidding::Account[account_id]
      registration_token = account.registration_token

      post '/api/v1/auth/verify',
           JSON.generate({ registration_token: registration_token }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
      response_body = JSON.parse(last_response.body)
      _(response_body['token']).wont_be_nil
      _(response_body['account']).must_be_kind_of Hash
      _(response_body['account']['id']).must_equal account_id
      _(response_body['account']['username']).must_equal 'verifyuser'
      _(response_body['account']['email']).must_equal 'verify@example.com'
    end

    it 'HAPPY: email_verified_at is set after verification' do
      stub_request(:post, 'https://send.api.mailtrap.io/api/send')
        .to_return(status: 200, body: JSON.generate({ ok: true }))

      post '/api/v1/auth/register',
           JSON.generate({ username: 'verifyuser2', email: 'verify2@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      register_response = JSON.parse(last_response.body)
      account_id = register_response['account_id']
      account = SecureBidding::Account[account_id]
      registration_token = account.registration_token

      post '/api/v1/auth/verify',
           JSON.generate({ registration_token: registration_token }),
           'CONTENT_TYPE' => 'application/json'

      verified_account = SecureBidding::Account[account_id]
      _(verified_account.email_verified_at).wont_be_nil
    end

    it 'HAPPY: session token is valid for ONE_WEEK' do
      stub_request(:post, 'https://send.api.mailtrap.io/api/send')
        .to_return(status: 200, body: JSON.generate({ ok: true }))

      post '/api/v1/auth/register',
           JSON.generate({ username: 'tokenuser', email: 'token@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      register_response = JSON.parse(last_response.body)
      account = SecureBidding::Account[register_response['account_id']]
      registration_token = account.registration_token

      post '/api/v1/auth/verify',
           JSON.generate({ registration_token: registration_token }),
           'CONTENT_TYPE' => 'application/json'

      response_body = JSON.parse(last_response.body)
      session_token = response_body['token']

      token_obj = SecureBidding::AuthToken.load(session_token)
      _(token_obj.fresh?).must_equal true
      _(token_obj.payload[:account_id]).must_equal register_response['account_id']
    end

    it 'SAD: returns 403 for expired token' do
      stub_request(:post, 'https://send.api.mailtrap.io/api/send')
        .to_return(status: 200, body: JSON.generate({ ok: true }))

      # Create a token manually that's already expired
      expired_token = SecureBidding::AuthToken.new(
        { account_id: 'test-id-123' },
        -3600  # Negative expiration = already expired
      ).to_s

      post '/api/v1/auth/verify',
           JSON.generate({ registration_token: expired_token }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 403
      response_body = JSON.parse(last_response.body)
      _(response_body['error']).must_include 'expired'
    end

    it 'SAD: returns 404 for invalid token' do
      post '/api/v1/auth/verify',
           JSON.generate({ registration_token: 'invalid_token_string' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 404
      response_body = JSON.parse(last_response.body)
      _(response_body['error']).wont_be_nil
    end

    it 'SAD: returns 400 for missing token' do
      post '/api/v1/auth/verify',
           JSON.generate({}),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 400
      response_body = JSON.parse(last_response.body)
      _(response_body['error']).must_include 'required'
    end
  end

  # Full flow test
  describe 'Full registration flow' do
    it 'HAPPY: completes availability check -> register -> verify flow' do
      stub_request(:post, 'https://send.api.mailtrap.io/api/send')
        .to_return(status: 200, body: JSON.generate({ ok: true }))

      # Step 1: Check availability
      post '/api/v1/auth/availability',
           JSON.generate({ username: 'fullflow', email: 'fullflow@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
      availability = JSON.parse(last_response.body)
      _(availability['available']['username']).must_equal true
      _(availability['available']['email']).must_equal true

      # Step 2: Register
      post '/api/v1/auth/register',
           JSON.generate({ username: 'fullflow', email: 'fullflow@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
      register_result = JSON.parse(last_response.body)
      account_id = register_result['account_id']

      # Step 3: Verify
      account = SecureBidding::Account[account_id]
      registration_token = account.registration_token

      post '/api/v1/auth/verify',
           JSON.generate({ registration_token: registration_token }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
      verify_result = JSON.parse(last_response.body)
      _(verify_result['token']).wont_be_nil
      _(verify_result['account']['username']).must_equal 'fullflow'

      # Verify account is now verified
      final_account = SecureBidding::Account[account_id]
      _(final_account.email_verified_at).wont_be_nil
    end
  end
end
# rubocop:enable Metrics/BlockLength
