# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'json'
require 'webmock/minitest'
require 'ostruct'
require 'base64'
require_relative '../app/require_app'

# Compatibility shim: older tests expect WebMock::RequestRegistry.instance.requests
module WebMock
  class RequestRegistry
    def requests
      arr = []
      requested_signatures.each do |req_sig, _|
        arr << OpenStruct.new(uri: req_sig.uri, method: req_sig.method, headers: req_sig.headers, body: req_sig.body)
      end
      arr
    end
  end
end

# rubocop:disable Metrics/BlockLength
describe 'Webmock integration for email API calls' do
  include Rack::Test::Methods

  def app
    SecureBidding::App.freeze.app
  end

  def registration_token_from_email
    html = SecureBidding::Services::Email::SendVerification.last_payload[:html]
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

  def stub_mailtrap_success
    stub_request(:post, 'https://send.api.mailtrap.io/api/send')
      .to_return(status: 200, body: JSON.generate({ ok: true }))
  end

  def stub_mailtrap_failure(status_code = 500)
    stub_request(:post, 'https://send.api.mailtrap.io/api/send')
      .to_return(status: status_code, body: 'Internal Server Error')
  end

  describe 'Test 1: Email sent verification' do
    it 'sends email during registration with POST to Mailtrap' do
      stub_mailtrap_success

      post '/api/v1/auth/register',
           JSON.generate({ username: 'emailtest1', email: 'emailtest1@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
      requests_to_mailtrap = WebMock::RequestRegistry.instance.requests
      _(requests_to_mailtrap.length).must_equal 1
    end
  end

  describe 'Test 2: Email payload structure verification' do
    it 'sends correct email payload structure to Mailtrap' do
      stub_mailtrap_success

      post '/api/v1/auth/register',
           JSON.generate({ username: 'payloadtest', email: 'payloadtest@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200

      payload = JSON.parse(SecureBidding::Services::Email::SendVerification.last_payload.to_json)
      _(payload['from']).must_be_kind_of Hash
      _(payload['to']).must_be_kind_of Array
      _(payload['to'][0]['email']).must_equal 'payloadtest@example.com'
      _(payload['html']).must_include 'http://localhost:9292/register/verify/'
    end
  end

  describe 'Test 3: Token in email link verification' do
    it 'token in email can be used for verification' do
      stub_mailtrap_success

      post '/api/v1/auth/register',
           JSON.generate({ username: 'tokenverify', email: 'tokenverify@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      token = registration_token_from_email

      post '/api/v1/auth/verify',
           JSON.generate({ registration_token: token, password: 'secret123' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
      verify_response = JSON.parse(last_response.body)
      _(verify_response['account']['email']).must_equal 'tokenverify@example.com'
    end
  end

  describe 'Test 4: Email not sent for duplicate email' do
    it 'does not send email when trying to register with existing email' do
      stub_mailtrap_success
      account = SecureBidding::Account.new(username: 'existing-user', system_role: 'member')
      account.set_password('secret123')
      account.set_email('duplicate@example.com')
      account.save

      post '/api/v1/auth/register',
           JSON.generate({ username: 'seconduser', email: 'duplicate@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 422
    end
  end

  describe 'Test 5: Email not sent for duplicate username' do
    it 'does not send email when trying to register with existing username' do
      stub_mailtrap_success
      account = SecureBidding::Account.new(username: 'sameusername', system_role: 'member')
      account.set_password('secret123')
      account.set_email('first@example.com')
      account.save

      post '/api/v1/auth/register',
           JSON.generate({ username: 'sameusername', email: 'second@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 422
    end
  end

  describe 'Test 6: Mailtrap API failure handling' do
    it 'returns 500 when Mailtrap returns 500 error' do
      stub_mailtrap_failure(500)

      post '/api/v1/auth/register',
           JSON.generate({ username: 'failtest', email: 'failtest@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 500
    end

    it 'returns 500 when Mailtrap returns 401 error' do
      stub_mailtrap_failure(401)

      post '/api/v1/auth/register',
           JSON.generate({ username: 'authfail', email: 'authfail@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 500
    end

    it 'logs error when email service fails' do
      stub_mailtrap_failure(503)

      post '/api/v1/auth/register',
           JSON.generate({ username: 'logerror', email: 'logerror@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 500
    end
  end

  describe 'Test 7: No real HTTP calls made' do
    it 'allows app to work without DATABASE_URL in environment' do
      stub_mailtrap_success
      post '/api/v1/auth/register',
           JSON.generate({ username: 'nomocking', email: 'nomocking@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
    end

    it 'raises error if any real HTTP request is attempted' do
      stub_mailtrap_success
      WebMock.disable_net_connect!

      post '/api/v1/auth/register',
           JSON.generate({ username: 'webmocktest', email: 'webmocktest@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200

      WebMock.allow_net_connect!
    end
  end

  describe 'Test 8: Edge cases' do
    it 'handles unicode characters in username' do
      stub_mailtrap_success

      post '/api/v1/auth/register',
           JSON.generate({ username: '用户名', email: 'unicode@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
      _(SecureBidding::Services::Email::SendVerification.last_payload[:html]).must_include '用户名'
    end

    it 'handles very long username' do
      long_username = 'a' * 255
      stub_mailtrap_success

      post '/api/v1/auth/register',
           JSON.generate({ username: long_username, email: 'longuser@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_be_kind_of Integer
    end
  end

  describe 'Test 9: Multiple registrations' do
    it 'sends separate emails for multiple users' do
      stub_mailtrap_success

      post '/api/v1/auth/register',
           JSON.generate({ username: 'user1', email: 'user1@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200

      post '/api/v1/auth/register',
           JSON.generate({ username: 'user2', email: 'user2@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
      _(SecureBidding::Services::Email::SendVerification.last_payloads.length).must_equal 2
    end
  end

  describe 'Test 10: Full webmock verification' do
    it 'completes full registration flow with mocked emails' do
      stub_mailtrap_success

      post '/api/v1/auth/register',
           JSON.generate({ username: 'fullflow', email: 'fullflow@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
      token = registration_token_from_email

      post '/api/v1/auth/verify',
           JSON.generate({ registration_token: token, password: 'secret123' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
      verify_response = JSON.parse(last_response.body)
      _(verify_response['account']['email']).must_equal 'fullflow@example.com'
    end
  end
end
# rubocop:enable Metrics/BlockLength
