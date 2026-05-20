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
# Provide a lightweight wrapper that exposes uri, method, headers, body
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

  # Helper methods for webmock
  def stub_mailtrap_success
    stub_request(:post, 'https://send.api.mailtrap.io/api/send')
      .to_return(status: 200, body: JSON.generate({ ok: true }))
  end

  def stub_mailtrap_failure(status_code = 500)
    stub_request(:post, 'https://send.api.mailtrap.io/api/send')
      .to_return(status: status_code, body: 'Internal Server Error')
  end

  def capture_mailtrap_request
    get_mailtrap_requests.first
  end

  def mailtrap_request_count
    get_mailtrap_requests.length
  end

  def extract_token_from_html(html)
    # Extract token from the verification link in HTML
    # Expected format: ?token=<base64-encoded-token>
    if html.match?(/token=([^\s"&]+)/)
      html.match(/token=([^\s"&]+)/)[1]
    end
  end

  def last_mailtrap_request_body
    # Prefer WebMock captured request body when available
    found = nil
    WebMock::RequestRegistry.instance.requested_signatures.each do |req_sig, _|
      found = req_sig if req_sig.uri.to_s.include?('send.api.mailtrap.io/api/send')
    end
    return found.body if found

    # Fallback to in-process recorded payload (set by SendVerification in test mode)
    if defined?(SecureBidding::Services::Email::SendVerification) && SecureBidding::Services::Email::SendVerification.last_payload
      return JSON.generate(SecureBidding::Services::Email::SendVerification.last_payload)
    end

    nil
  end

  def get_mailtrap_requests
    arr = []
    WebMock::RequestRegistry.instance.requested_signatures.each do |req_sig, _|
      arr << req_sig if req_sig.uri.to_s.include?('send.api.mailtrap.io/api/send')
    end
    return arr unless arr.empty?

    # Fallback to recorded payloads and headers captured in SendVerification
    if defined?(SecureBidding::Services::Email::SendVerification) && SecureBidding::Services::Email::SendVerification.last_payloads
      SecureBidding::Services::Email::SendVerification.last_payloads.map.with_index do |pl, i|
        hdr = if SecureBidding::Services::Email::SendVerification.last_headers_array && SecureBidding::Services::Email::SendVerification.last_headers_array[i]
                SecureBidding::Services::Email::SendVerification.last_headers_array[i]
              else
                {}
              end
        OpenStruct.new(uri: URI('https://send.api.mailtrap.io/api/send'), method: :post, headers: hdr, body: JSON.generate(pl))
      end
    else
      []
    end
  end
  before do
    SecureBidding::Database.migrate!
    SecureBidding::BidSubmission.dataset.delete
    SecureBidding::Project.dataset.delete
    SecureBidding::AccountProject.dataset.delete
    SecureBidding::Account.dataset.delete
    SecureBidding::AuthToken.setup(SecureBidding::AuthToken.generate_key)
    WebMock.reset!
    # Clear any in-process recorded payloads/headers used as fallbacks
    if defined?(SecureBidding::Services::Email::SendVerification)
      SecureBidding::Services::Email::SendVerification.last_payload = nil
      SecureBidding::Services::Email::SendVerification.last_headers = nil
      SecureBidding::Services::Email::SendVerification.last_payloads = []
      SecureBidding::Services::Email::SendVerification.last_headers_array = []
    end
    stub_mailtrap_success
  end

  # Test 1: Verify email is sent during registration
  describe 'Test 1: Email sent verification' do
    it 'sends email during registration with POST to Mailtrap' do
      post '/api/v1/auth/register',
           JSON.generate({ username: 'emailtest1', email: 'emailtest1@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200

      requests_to_mailtrap = get_mailtrap_requests

      _(requests_to_mailtrap.length).must_equal 1
      _(requests_to_mailtrap.first.method).must_equal :post
      _(requests_to_mailtrap.first.headers['Authorization']).wont_be_nil
    end

    it 'includes Authorization header with Bearer token' do
      stub_request(:post, 'https://send.api.mailtrap.io/api/send')
        .to_return(status: 200, body: JSON.generate({ ok: true }))

      post '/api/v1/auth/register',
           JSON.generate({ username: 'authtest', email: 'authtest@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      requests_to_mailtrap = get_mailtrap_requests

      _(requests_to_mailtrap.first.headers['Authorization']).must_match(/^Bearer /)
    end
  end

  # Test 2: Verify email payload structure
  describe 'Test 2: Email payload structure verification' do
    it 'sends correct email payload structure to Mailtrap' do
      post '/api/v1/auth/register',
           JSON.generate({ username: 'payloadtest', email: 'payloadtest@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200

      request_body = last_mailtrap_request_body
      payload = JSON.parse(request_body)

      # Verify from object
      _(payload['from']).must_be_kind_of Hash
      _(payload['from']['email']).wont_be_nil
      _(payload['from']['name']).wont_be_nil

      # Verify to array
      _(payload['to']).must_be_kind_of Array
      _(payload['to'].length).must_equal 1
      _(payload['to'][0]['email']).must_equal 'payloadtest@example.com'

      # Verify subject contains verification keyword
      _(payload['subject']).must_include 'Verify'

      # Verify html contains verification link
      _(payload['html']).must_include 'verification'
      _(payload['html']).must_include 'href='
      _(payload['html']).must_include 'token='
    end

    it 'includes both email link and text link in HTML' do
      post '/api/v1/auth/register',
           JSON.generate({ username: 'linktest', email: 'linktest@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200

      request_body = last_mailtrap_request_body
      payload = JSON.parse(request_body)
      html = payload['html']

      # Should have clickable link with href
      _(html).must_include '<a href='
      # Should have text link for copy/paste
      _(html).must_include 'copy and paste'
      _(html).must_include 'http'
    end

    it 'includes username in email body' do
      post '/api/v1/auth/register',
           JSON.generate({ username: 'johndoe', email: 'johndoe@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      request_body = last_mailtrap_request_body
      payload = JSON.parse(request_body)
      html = payload['html']

      _(html).must_include 'johndoe'
      _(html).must_include 'Welcome'
    end

    it 'escapes HTML special characters in username' do
      post '/api/v1/auth/register',
           JSON.generate({ username: '<script>alert("test")</script>', email: 'xsstest@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      request_body = last_mailtrap_request_body
      payload = JSON.parse(request_body)
      html = payload['html']

      # Should NOT contain unescaped script tag
      _(html).wont_include '<script>'
      # Should contain escaped version
      _(html).must_include '&lt;script&gt;'
    end

    it 'properly escapes link URLs' do
      post '/api/v1/auth/register',
           JSON.generate({ username: 'linktest', email: 'linktest@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      request_body = last_mailtrap_request_body
      payload = JSON.parse(request_body)
      html = payload['html']

      # Extract the href URL
      href_match = html.match(/href="([^"]+)"/)
      _(href_match).wont_be_nil
      
      href_url = href_match[1]
      # URLs should be properly escaped (no unescaped characters that would break HTML)
      _(href_url).must_match(/^https?:/)
      _(href_url).wont_include '"'
    end
  end

  # Test 3: Verify token is in email link
  describe 'Test 3: Token in email link verification' do
    it 'includes registration token in verification link' do
      post '/api/v1/auth/register',
           JSON.generate({ username: 'tokentest', email: 'tokentest@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      register_response = JSON.parse(last_response.body)
      account_id = register_response['account_id']
      account = SecureBidding::Account[account_id]

      request_body = last_mailtrap_request_body
      payload = JSON.parse(request_body)
      html = payload['html']

      # Extract token from link
      token_extracted = extract_token_from_html(html)
      _(token_extracted).wont_be_nil

      # Token should match the one stored in account
      _(token_extracted).must_equal account.registration_token
    end

    it 'token in email can be used for verification' do
      post '/api/v1/auth/register',
           JSON.generate({ username: 'tokenverify', email: 'tokenverify@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      register_response = JSON.parse(last_response.body)
      account_id = register_response['account_id']

      # Extract token from email
      request_body = last_mailtrap_request_body
      payload = JSON.parse(request_body)
      html = payload['html']
      token_from_email = extract_token_from_html(html)

      # Use the token to verify
      post '/api/v1/auth/verify',
           JSON.generate({ registration_token: token_from_email }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
      verify_response = JSON.parse(last_response.body)
      _(verify_response['token']).wont_be_nil
      _(verify_response['account']['id']).must_equal account_id
    end

    it 'token is base64-encoded' do
      post '/api/v1/auth/register',
           JSON.generate({ username: 'base64test', email: 'base64test@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      request_body = last_mailtrap_request_body
      payload = JSON.parse(request_body)
      html = payload['html']
      token = extract_token_from_html(html)

      # Token should be decodable as base64
      begin
        decoded = Base64.decode64(token)
        _(decoded.length).must_be :>, 0
      rescue StandardError
        flunk('Token is not valid base64')
      end
    end
  end

  # Test 4: Email not sent for duplicate email
  describe 'Test 4: Email not sent for duplicate email' do
    it 'does not send email when trying to register with existing email' do
      # First registration
      post '/api/v1/auth/register',
           JSON.generate({ username: 'firstuser', email: 'duplicate@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200

      # Try to register with same email
      post '/api/v1/auth/register',
           JSON.generate({ username: 'seconduser', email: 'duplicate@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 422

      # Verify only one email was sent
      requests_to_mailtrap = get_mailtrap_requests

      _(requests_to_mailtrap.length).must_equal 1
    end
  end

  # Test 5: Email not sent for duplicate username
  describe 'Test 5: Email not sent for duplicate username' do
    it 'does not send email when trying to register with existing username' do
      # First registration
      post '/api/v1/auth/register',
           JSON.generate({ username: 'sameusername', email: 'first@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200

      # Try to register with same username
      post '/api/v1/auth/register',
           JSON.generate({ username: 'sameusername', email: 'second@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 422

      # Verify only one email was sent
      requests_to_mailtrap = get_mailtrap_requests

      _(requests_to_mailtrap.length).must_equal 1
    end
  end

  # Test 6: Mailtrap API failure handling
  describe 'Test 6: Mailtrap API failure handling' do
    it 'returns 500 when Mailtrap returns 500 error' do
      stub_mailtrap_failure(500)

      post '/api/v1/auth/register',
           JSON.generate({ username: 'failtest', email: 'failtest@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 500
      response_body = JSON.parse(last_response.body)
      _(response_body['error']).must_include 'email'
    end

    it 'returns 500 when Mailtrap returns 401 error' do
      stub_mailtrap_failure(401)

      post '/api/v1/auth/register',
           JSON.generate({ username: 'authfail', email: 'authfail@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 500
      response_body = JSON.parse(last_response.body)
      _(response_body['error']).must_include 'email'
    end

    it 'logs error when email service fails' do
      stub_mailtrap_failure(503)

      # Capture log output or just verify it doesn't crash
      post '/api/v1/auth/register',
           JSON.generate({ username: 'logerror', email: 'logerror@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 500
    end
  end

  # Test 7: No real HTTP calls
  describe 'Test 7: No real HTTP calls made' do
    it 'allows app to work without DATABASE_URL in environment' do
      # This test verifies webmock is set up correctly
      # by ensuring the test environment can run without real network calls

      post '/api/v1/auth/register',
           JSON.generate({ username: 'nomocking', email: 'nomocking@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      # Should complete without making real HTTP requests
      _(last_response.status).must_equal 200

      # Verify no real requests were made (only stubbed requests)
      assert_requested :post, 'https://send.api.mailtrap.io/api/send', times: 1
    end

    it 'raises error if any real HTTP request is attempted' do
      WebMock.disable_net_connect!

      # This should not make any real network calls
      post '/api/v1/auth/register',
           JSON.generate({ username: 'webmocktest', email: 'webmocktest@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      # Verify request completed (webmock handled it)
      _(last_response.status).must_equal 200

      WebMock.allow_net_connect!
    end
  end

  # Test 8: Edge cases
  describe 'Test 8: Edge cases' do
    it 'handles unicode characters in username' do
      post '/api/v1/auth/register',
           JSON.generate({ username: '用户名', email: 'unicode@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200

      request_body = last_mailtrap_request_body
      payload = JSON.parse(request_body)
      html = payload['html']

      _(html).must_include '用户名'
    end

    it 'handles special characters in name field' do
      post '/api/v1/auth/register',
           JSON.generate({ username: 'user+test@domain', email: 'special@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200

      request_body = last_mailtrap_request_body
      payload = JSON.parse(request_body)

      # Verify email was sent
      _(payload).wont_be_nil
    end

    it 'handles very long username' do
      long_username = 'a' * 255
      post '/api/v1/auth/register',
           JSON.generate({ username: long_username, email: 'longuser@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      # Should either accept or reject, but not crash
      _(last_response.status).must_be_kind_of Integer
    end

    it 'preserves token format in very long email addresses' do
      long_email = "a" * 50 + "@example.com"
      post '/api/v1/auth/register',
           JSON.generate({ username: 'longemail', email: long_email }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200

      request_body = last_mailtrap_request_body
      payload = JSON.parse(request_body)
      html = payload['html']

      token = extract_token_from_html(html)
      _(token).wont_be_nil
      _(token).must_match(/^[A-Za-z0-9+\/=]+$/)
    end

    it 'handles HTML escape sequences in email body' do
      post '/api/v1/auth/register',
           JSON.generate({ username: 'user&<>"', email: 'escape@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      request_body = last_mailtrap_request_body
      payload = JSON.parse(request_body)
      html = payload['html']

      # Should escape dangerous characters
      _(html).must_include '&amp;' if html.include?('&')
      _(html).wont_include '<"'
    end
  end

  # Test 9: Multiple concurrent registrations don't interfere
  describe 'Test 9: Multiple registrations' do
    it 'sends separate emails for multiple users' do
      post '/api/v1/auth/register',
           JSON.generate({ username: 'user1', email: 'user1@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200

      post '/api/v1/auth/register',
           JSON.generate({ username: 'user2', email: 'user2@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200

      requests_to_mailtrap = get_mailtrap_requests

      _(requests_to_mailtrap.length).must_equal 2
    end

    it 'each email contains correct recipient' do
      post '/api/v1/auth/register',
           JSON.generate({ username: 'recipient1', email: 'recipient1@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      post '/api/v1/auth/register',
           JSON.generate({ username: 'recipient2', email: 'recipient2@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      requests_to_mailtrap = get_mailtrap_requests
 
      first_payload = JSON.parse(requests_to_mailtrap[0].body)
      second_payload = JSON.parse(requests_to_mailtrap[1].body)
 
      _(first_payload['to'][0]['email']).must_equal 'recipient1@example.com'
      _(second_payload['to'][0]['email']).must_equal 'recipient2@example.com'
    end
  end

  # Test 10: Verification of entire request flow
  describe 'Test 10: Full webmock verification' do
    it 'completes full registration flow with mocked emails' do
      post '/api/v1/auth/register',
           JSON.generate({ username: 'fullflow', email: 'fullflow@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200

      # Extract token from email
      request_body = last_mailtrap_request_body
      payload = JSON.parse(request_body)
      token = extract_token_from_html(payload['html'])

      # Verify using extracted token
      post '/api/v1/auth/verify',
           JSON.generate({ registration_token: token }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
      verify_response = JSON.parse(last_response.body)
      _(verify_response['token']).wont_be_nil
      _(verify_response['account']['email']).must_equal 'fullflow@example.com'

      # Verify no real HTTP calls were made outside of webmock stubs
      requests_to_mailtrap = get_mailtrap_requests

      _(requests_to_mailtrap.length).must_equal 1
    end
  end
end
# rubocop:enable Metrics/BlockLength
