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

  def registration_email_payload
    SecureBidding::Services::Email::SendVerification.last_payload
  end

  def registration_token_from_email
    html = registration_email_payload.fetch(:html)
    html.match(%r{/register/verify/([^"<\s]+)})[1]
  end

  before do
    SecureBidding::Database.migrate!
    SecureBidding::BidSubmission.dataset.delete
    SecureBidding::Project.dataset.delete
    SecureBidding::AccountProject.dataset.delete
    SecureBidding::Account.dataset.delete
    SecureBidding::AuthToken.setup(SecureBidding::AuthToken.generate_key)
    WebMock.reset!
    SecureBidding::Services::Email::SendVerification.last_payload = nil
    SecureBidding::Services::Email::SendVerification.last_headers = nil
    SecureBidding::Services::Email::SendVerification.last_payloads = []
    SecureBidding::Services::Email::SendVerification.last_headers_array = []
    ENV['FRONTEND_APP_URL'] = 'http://localhost:9292'
  end

  # POST /api/v1/auth/availability tests
  describe 'POST /api/v1/auth/availability' do
    it 'HAPPY: returns available true for new username and email' do
      post '/api/v1/auth/availability',
           JSON.generate({ username: 'newuser', email: 'new@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
      response_body = JSON.parse(last_response.body)
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
    it 'HAPPY: sends verification email without creating the account' do
      stub_request(:post, 'https://send.api.mailtrap.io/api/send')
        .to_return(status: 200, body: JSON.generate({ ok: true }))

      post '/api/v1/auth/register',
           JSON.generate({ username: 'scifiengineering', email: 'scifithedev@gapp.nthu.edu.tw' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
      response_body = JSON.parse(last_response.body)
      _(response_body['message']).must_include 'Check your email'
      _(response_body['account_id']).must_be_nil

      stored = SecureBidding::Account.where(username: 'scifiengineering').first
      _(stored).must_be_nil

      html = registration_email_payload[:html]
      _(html).must_include 'scifiengineering'
      _(html).must_include 'http://localhost:9292/register/verify/'
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
      _(SecureBidding::Account.where(username: 'mailuser').first).must_be_nil
    end

    it 'SAD: does not persist account when Mailtrap returns 400' do
      stub_request(:post, 'https://send.api.mailtrap.io/api/send')
        .to_return(status: 400, body: 'Bad Request')

      post '/api/v1/auth/register',
           JSON.generate({ username: 'badrequestuser', email: 'badrequest@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 500
      _(SecureBidding::Account.where(username: 'badrequestuser').first).must_be_nil
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

      registration_token = registration_token_from_email

      post '/api/v1/auth/verify',
           JSON.generate({ registration_token: registration_token, password: 'secret123' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
      response_body = JSON.parse(last_response.body)
      _(response_body['token']).wont_be_nil
      _(response_body['account']).must_be_kind_of Hash
      _(response_body['account']['username']).must_equal 'verifyuser'
      _(response_body['account']['email']).must_equal 'verify@example.com'

      account = SecureBidding::Account.where(username: 'verifyuser').first
      _(account).wont_be_nil
      _(account.check_password('secret123')).must_equal true
      _(account.email_verified_at).wont_be_nil
    end

    it 'HAPPY: creates the account only after verification' do
      stub_request(:post, 'https://send.api.mailtrap.io/api/send')
        .to_return(status: 200, body: JSON.generate({ ok: true }))

      post '/api/v1/auth/register',
           JSON.generate({ username: 'pendinguser', email: 'pending@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(SecureBidding::Account.where(username: 'pendinguser').first).must_be_nil
    end

    it 'SAD: returns 403 for expired token' do
      expired_token = SecureBidding::AuthToken.new(
        { username: 'expired', email: 'expired@example.com', system_role: 'member' },
        -3600
      ).to_s

      post '/api/v1/auth/verify',
           JSON.generate({ registration_token: expired_token, password: 'secret123' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 403
      response_body = JSON.parse(last_response.body)
      _(response_body['error']).must_include 'expired'
    end

    it 'SAD: returns 404 for invalid token' do
      post '/api/v1/auth/verify',
           JSON.generate({ registration_token: 'invalid_token_string', password: 'secret123' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 404
      response_body = JSON.parse(last_response.body)
      _(response_body['error']).wont_be_nil
    end

    it 'SAD: returns 400 for missing token' do
      post '/api/v1/auth/verify',
           JSON.generate({ password: 'secret123' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 400
      response_body = JSON.parse(last_response.body)
      _(response_body['error']).must_include 'required'
    end

    it 'SAD: returns 400 for missing password' do
      post '/api/v1/auth/verify',
           JSON.generate({ registration_token: 'token-value' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 400
      response_body = JSON.parse(last_response.body)
      _(response_body['error']).must_include 'password'
    end
  end

  # Full flow test
  describe 'Full registration flow' do
    it 'HAPPY: completes availability check -> register -> verify flow' do
      stub_request(:post, 'https://send.api.mailtrap.io/api/send')
        .to_return(status: 200, body: JSON.generate({ ok: true }))

      post '/api/v1/auth/availability',
           JSON.generate({ username: 'fullflow', email: 'fullflow@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
      availability = JSON.parse(last_response.body)
      _(availability['available']['username']).must_equal true
      _(availability['available']['email']).must_equal true

      post '/api/v1/auth/register',
           JSON.generate({ username: 'fullflow', email: 'fullflow@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
      token = registration_token_from_email

      post '/api/v1/auth/verify',
           JSON.generate({ registration_token: token, password: 'top-secret-123' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
      verify_result = JSON.parse(last_response.body)
      _(verify_result['token']).wont_be_nil
      _(verify_result['account']['username']).must_equal 'fullflow'

      final_account = SecureBidding::Account.where(username: 'fullflow').first
      _(final_account).wont_be_nil
      _(final_account.email_verified_at).wont_be_nil
    end
  end
end
# rubocop:enable Metrics/BlockLength
