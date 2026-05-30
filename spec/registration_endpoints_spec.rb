# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'json'
require 'minitest/autorun'
require 'net/smtp'
require 'rack/test'
require_relative '../app/require_app'

# rubocop:disable Metrics/BlockLength
describe 'API /api/v1/auth registration endpoints' do
  include Rack::Test::Methods

  class FakeSMTP
    attr_reader :started_with, :messages

    def initialize
      @messages = []
    end

    def enable_starttls_auto; end

    def start(domain, username, password, auth)
      @started_with = {
        domain: domain,
        username: username,
        password: password,
        auth: auth
      }
      yield self
    end

    def send_message(message, from, to)
      @messages << {
        message: message,
        from: from,
        to: to
      }
    end
  end

  def app
    SecureBidding::App.freeze.app
  end

  def with_mailer_togo_env
    original = {}
    original = {
      'MAILERTOGO_URL' => ENV['MAILERTOGO_URL'],
      'MAILERTOGO_FROM_EMAIL' => ENV['MAILERTOGO_FROM_EMAIL'],
      'MAILERTOGO_FROM_NAME' => ENV['MAILERTOGO_FROM_NAME']
    }

    ENV['MAILERTOGO_URL'] = 'smtp://mailertogo-user:mailertogo-password@smtp.us-west-1.mailertogo.net:587?authentication=plain'
    ENV['MAILERTOGO_FROM_EMAIL'] = 'securebidfreelanceprocurementh@gmail.com'
    ENV['MAILERTOGO_FROM_NAME'] = 'Secure Bidding API'
    yield
  ensure
    original.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  def extract_registration_token(message)
    match = message.match(/token=([^"&\s<]+)/)
    match && match[1]
  end

  before do
    SecureBidding::Database.migrate!
    SecureBidding::BidSubmission.dataset.delete
    SecureBidding::Project.dataset.delete
    SecureBidding::AccountProject.dataset.delete
    SecureBidding::Account.dataset.delete
    SecureBidding::AuthToken.setup(SecureBidding::AuthToken.generate_key)
    @fake_smtp = FakeSMTP.new
    @original_smtp_new = Net::SMTP.method(:new)
    fake_smtp = @fake_smtp
    Net::SMTP.define_singleton_method(:new) do |_host, _port|
      fake_smtp
    end
  end

  after do
    Net::SMTP.define_singleton_method(:new, &@original_smtp_new.to_proc)
  end

  describe 'POST /api/v1/auth/availability' do
    it 'returns available true for new username and email' do
      post '/api/v1/auth/availability',
           JSON.generate({ username: 'newuser', email: 'new@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
      response_body = JSON.parse(last_response.body)
      _(response_body['available']['username']).must_equal true
      _(response_body['available']['email']).must_equal true
    end
  end

  describe 'POST /api/v1/auth/register' do
    it 'sends a verification email without persisting the account' do
      with_mailer_togo_env do
        post '/api/v1/auth/register',
             JSON.generate({ username: 'newregister', email: 'register@example.com' }),
             'CONTENT_TYPE' => 'application/json'
      end

      _(last_response.status).must_equal 200
      response_body = JSON.parse(last_response.body)
      _(response_body['message']).must_include 'Check your email'
      _(response_body).wont_include 'account_id'

      _(SecureBidding::Account.where(username: 'newregister').count).must_equal 0
      _(SecureBidding::Account.where(email_hash: SecureBidding::Account.search_hash('register@example.com')).count).must_equal 0
      _( @fake_smtp.messages.length).must_equal 1
      _( @fake_smtp.messages.first[:from]).must_equal 'securebidfreelanceprocurementh@gmail.com'
      _( @fake_smtp.messages.first[:to]).must_equal 'register@example.com'

      token = extract_registration_token(@fake_smtp.messages.first[:message])
      _(token).wont_be_nil
      token_payload = SecureBidding::AuthToken.load(token).payload
      _(token_payload[:username]).must_equal 'newregister'
      _(token_payload[:email]).must_equal 'register@example.com'
    end

    it 'returns 400 for missing email' do
      with_mailer_togo_env do
        post '/api/v1/auth/register',
             JSON.generate({ username: 'testuser' }),
             'CONTENT_TYPE' => 'application/json'
      end

      _(last_response.status).must_equal 400
      response_body = JSON.parse(last_response.body)
      error = response_body['error']
      error_text = error.is_a?(Hash) ? error.values.flatten.join(' ') : error.to_s
      _(error_text).must_match(/missing|required/i)
    end

    it 'returns 422 for taken email' do
      account = SecureBidding::Account.new(username: 'existing', system_role: 'member')
      account.set_password('testpass123')
      account.set_email('taken@example.com')
      account.save

      with_mailer_togo_env do
        post '/api/v1/auth/register',
             JSON.generate({ username: 'newuser', email: 'taken@example.com' }),
             'CONTENT_TYPE' => 'application/json'
      end

      _(last_response.status).must_equal 422
      response_body = JSON.parse(last_response.body)
      _(response_body['error']).must_include 'email'
    end

    it 'returns 500 if the email service fails' do
      ENV['MAILERTOGO_URL'] = 'smtp://mailertogo-user:@smtp.us-west-1.mailertogo.net:587?authentication=plain'

      post '/api/v1/auth/register',
           JSON.generate({ username: 'mailuser', email: 'mail@example.com' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 500
      response_body = JSON.parse(last_response.body)
      _(response_body['error']).must_include 'email'
    ensure
      ENV['MAILERTOGO_URL'] = 'smtp://mailertogo-user:mailertogo-password@smtp.us-west-1.mailertogo.net:587?authentication=plain'
    end
  end

  describe 'POST /api/v1/auth/verify' do
    it 'creates the account during verification and returns a session token' do
      with_mailer_togo_env do
        post '/api/v1/auth/register',
             JSON.generate({ username: 'verifyuser', email: 'verify@example.com' }),
             'CONTENT_TYPE' => 'application/json'
      end

      token = extract_registration_token(@fake_smtp.messages.first[:message])

      post '/api/v1/auth/verify',
           JSON.generate({ registration_token: token, password: 'chosen_password_123' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
      response_body = JSON.parse(last_response.body)
      _(response_body['token']).wont_be_nil
      _(response_body['account']['id']).wont_be_nil
      _(response_body['account']['username']).must_equal 'verifyuser'
      _(response_body['account']['email']).must_equal 'verify@example.com'

      account = SecureBidding::Account[response_body['account']['id']]
      _(account.email_verified_at).wont_be_nil

      post '/api/v1/auth/authenticate',
           JSON.generate({ username: 'verifyuser', password: 'chosen_password_123' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
    end

    it 'returns 404 for an invalid token' do
      post '/api/v1/auth/verify',
           JSON.generate({ registration_token: 'invalid_token_string', password: 'password123' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 404
      response_body = JSON.parse(last_response.body)
      _(response_body['error']).wont_be_nil
    end
  end
end
# rubocop:enable Metrics/BlockLength
