# frozen_string_literal: true

require_relative 'spec_helper'
require 'net/smtp'

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
    match = message.match(%r{register/verify/([^"&\s<]+)}) ||
            message.match(/token=([^"&\s<]+)/)
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
      signed_post '/api/v1/auth/availability',
           { username: 'newuser', email: 'new@example.com' }

      _(last_response.status).must_equal 200
      response_body = JSON.parse(last_response.body)
      _(response_body['available']['username']).must_equal true
      _(response_body['available']['email']).must_equal true
    end
  end

  describe 'POST /api/v1/auth/register' do
    it 'sends a verification email without persisting the account' do
      with_mailer_togo_env do
        signed_post '/api/v1/auth/register',
           { username: 'newregister', email: 'register@example.com' }
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
        signed_post '/api/v1/auth/register',
           { username: 'testuser' }
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
        signed_post '/api/v1/auth/register',
           { username: 'newuser', email: 'taken@example.com' }
      end

      _(last_response.status).must_equal 422
      response_body = JSON.parse(last_response.body)
      _(response_body['error']).must_include 'email'
    end

    it 'returns 500 if the email service fails' do
      original_url = ENV['MAILERTOGO_URL']
      original_password = ENV['MAILERTOGO_SMTP_PASSWORD']
      original_password_lower = ENV['mailertogo_smtp_password']

      ENV['MAILERTOGO_URL'] = nil
      ENV.delete('mailertogo_url')
      ENV['MAILERTOGO_SMTP_HOST'] = 'smtp.us-west-1.mailertogo.net'
      ENV['MAILERTOGO_SMTP_PORT'] = '587'
      ENV['MAILERTOGO_SMTP_USER'] = 'mailertogo-user'
      ENV['MAILERTOGO_SMTP_PASSWORD'] = ''
      ENV.delete('mailertogo_smtp_password')

      signed_post '/api/v1/auth/register',
           { username: 'mailuser', email: 'mail@example.com' }

      _(last_response.status).must_equal 500
      response_body = JSON.parse(last_response.body)
      _(response_body['error']).must_include 'email'
    ensure
      ENV['MAILERTOGO_URL'] = original_url
      if original_password.nil?
        ENV.delete('MAILERTOGO_SMTP_PASSWORD')
      else
        ENV['MAILERTOGO_SMTP_PASSWORD'] = original_password
      end
      if original_password_lower.nil?
        ENV.delete('mailertogo_smtp_password')
      else
        ENV['mailertogo_smtp_password'] = original_password_lower
      end
    end
  end

  describe 'POST /api/v1/auth/verify' do
    it 'creates the account during verification and returns a session token' do
      with_mailer_togo_env do
        signed_post '/api/v1/auth/register',
           { username: 'verifyuser', email: 'verify@example.com' }
      end

      token = extract_registration_token(@fake_smtp.messages.first[:message])

      signed_post '/api/v1/auth/verify',
           { registration_token: token, password: 'chosen_password_123' }

      _(last_response.status).must_equal 200
      response_body = JSON.parse(last_response.body)
      _(response_body['token']).wont_be_nil
      _(response_body['account']['id']).wont_be_nil
      _(response_body['account']['username']).must_equal 'verifyuser'
      _(response_body['account']['email']).must_equal 'verify@example.com'
      _(response_body['account']['email_verified']).must_equal true

      account = SecureBidding::Account[response_body['account']['id']]
      _(account.email_verified_at).wont_be_nil

      signed_post '/api/v1/auth/authenticate',
           { username: 'verifyuser', password: 'chosen_password_123' }

      _(last_response.status).must_equal 200
    end

    it 'returns 404 for an invalid token' do
      signed_post '/api/v1/auth/verify',
           { registration_token: 'invalid_token_string', password: 'password123' }

      _(last_response.status).must_equal 404
      response_body = JSON.parse(last_response.body)
      _(response_body['error']).wont_be_nil
    end
  end

  describe 'POST /api/v1/auth/verification-preview' do
    it 'returns username, email, and purpose for a registration token' do
      token = SecureBidding::AuthToken.tokenize(
        { username: 'preview-user', email: 'preview@example.com' },
        SecureBidding::AuthToken::VERIFICATION_LINK_TTL
      )

      signed_post '/api/v1/auth/verification-preview',
           { registration_token: token }

      _(last_response.status).must_equal 200
      response_body = JSON.parse(last_response.body)
      _(response_body['purpose']).must_equal 'registration'
      _(response_body['username']).must_equal 'preview-user'
      _(response_body['email']).must_equal 'preview@example.com'
    end

    it 'returns email_verification purpose for an existing account token' do
      account = SecureBidding::Account.new(username: 'preview-existing', system_role: 'member')
      account.set_email('preview-existing@example.com')
      account.set_password('password123')
      account.save
      account.set_registration_token
      account.save

      signed_post '/api/v1/auth/verification-preview',
           { registration_token: account.registration_token }

      _(last_response.status).must_equal 200
      response_body = JSON.parse(last_response.body)
      _(response_body['purpose']).must_equal 'email_verification'
      _(response_body['username']).must_equal 'preview-existing'
      _(response_body['email']).must_equal 'preview-existing@example.com'
    end
  end

  describe 'POST /api/v1/auth/registration-preview' do
    it 'remains available as an alias for verification-preview' do
      token = SecureBidding::AuthToken.tokenize(
        { username: 'preview-user', email: 'preview@example.com' },
        SecureBidding::AuthToken::VERIFICATION_LINK_TTL
      )

      signed_post '/api/v1/auth/registration-preview',
           { registration_token: token }

      _(last_response.status).must_equal 200
      response_body = JSON.parse(last_response.body)
      _(response_body['purpose']).must_equal 'registration'
      _(response_body['username']).must_equal 'preview-user'
      _(response_body['email']).must_equal 'preview@example.com'
    end
  end

  describe 'POST /api/v1/auth/verify-email' do
    it 'marks an existing account as verified when the resend token is valid' do
      account = SecureBidding::Account.new(username: 'verify-email-user', system_role: 'member')
      account.set_email('verify-email@example.com')
      account.set_password('password123')
      account.save
      account.set_registration_token
      account.save

      signed_post '/api/v1/auth/verify-email',
           { registration_token: account.registration_token }

      _(last_response.status).must_equal 200
      response_body = JSON.parse(last_response.body)
      _(response_body['email_verified']).must_equal true
      _(response_body['status']).must_equal 'verified'

      refreshed = SecureBidding::Account[account.id]
      _(refreshed.email_verified_at).wont_be_nil
      _(refreshed.registration_token).must_be_nil
    end

    it 'returns 404 for an unknown resend token' do
      signed_post '/api/v1/auth/verify-email',
           { registration_token: 'not-a-valid-token' }

      _(last_response.status).must_equal 404
    end
  end
end
# rubocop:enable Metrics/BlockLength
