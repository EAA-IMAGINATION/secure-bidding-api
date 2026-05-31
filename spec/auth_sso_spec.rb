# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'
ENV['GOOGLE_CLIENT_ID'] ||= 'test-client-id.apps.googleusercontent.com'

require 'minitest/autorun'
require 'rack/test'
require 'json'
require 'webmock/minitest'
require_relative '../app/require_app'

describe 'API /api/v1/auth/sso' do
  include Rack::Test::Methods

  def app
    SecureBidding::App.freeze.app
  end

  before do
    SecureBidding::AuthToken.setup(SecureBidding::AuthToken.generate_key)
    SecureBidding::Database.migrate!
    SecureBidding::SsoIdentity.dataset.delete
    SecureBidding::Account.dataset.delete
  end

  it 'creates an account from a verified Google id_token' do
    claims = {
      'sub' => 'google-subject-123',
      'email' => 'sso-user@example.com',
      'email_verified' => true,
      'name' => 'SSO User',
      'picture' => 'https://example.com/avatar.png',
      'iss' => 'https://accounts.google.com',
      'aud' => ENV.fetch('GOOGLE_CLIENT_ID')
    }

    original = SecureBidding::GoogleIdToken.method(:verify)
    SecureBidding::GoogleIdToken.define_singleton_method(:verify) { |_token| claims }
    begin
      post '/api/v1/auth/sso',
           JSON.generate({ id_token: 'fake.id.token' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 200
      body = JSON.parse(last_response.body)
      _(body['username']).wont_be_nil
      _(body['email']).must_equal 'sso-user@example.com'
      _(body['token']).wont_be_nil
      _(SecureBidding::SsoIdentity.count).must_equal 1
    ensure
      SecureBidding::GoogleIdToken.define_singleton_method(:verify, original)
    end
  end

  it 'returns 401 for invalid id_token' do
    original = SecureBidding::GoogleIdToken.method(:verify)
    SecureBidding::GoogleIdToken.define_singleton_method(:verify) do |_token|
      raise SecureBidding::OidcVerifier::VerificationError, 'bad token'
    end
    begin
      post '/api/v1/auth/sso',
           JSON.generate({ id_token: 'bad' }),
           'CONTENT_TYPE' => 'application/json'

      _(last_response.status).must_equal 401
    ensure
      SecureBidding::GoogleIdToken.define_singleton_method(:verify, original)
    end
  end
end

describe 'GET /api/v1/accounts/:username' do
  include Rack::Test::Methods

  def app
    SecureBidding::App.freeze.app
  end

  before do
    SecureBidding::AuthToken.setup(SecureBidding::AuthToken.generate_key)
    SecureBidding::Database.migrate!
    SecureBidding::Account.dataset.delete

    @account = SecureBidding::Account.new(username: 'scope-user', system_role: 'member')
    @account.set_password('secret-pass')
    @account.set_email('scope-user@example.com')
    @account.save
  end

  it 'returns a read-only api_key for self-view' do
    token = SecureBidding::AuthToken.new(
      { account_id: @account.id, username: @account.username, system_role: @account.system_role },
      SecureBidding::AuthToken::ONE_HOUR,
      scope: SecureBidding::AuthScope.new
    ).to_s

    get '/api/v1/accounts/scope-user', '', 'HTTP_AUTHORIZATION' => "Bearer #{token}"

    _(last_response.status).must_equal 200
    body = JSON.parse(last_response.body)
    _(body['username']).must_equal 'scope-user'
    _(body['api_key']).wont_be_nil

    loaded = SecureBidding::AuthToken.load(body['api_key'])
    _(loaded.scope.to_s).must_equal SecureBidding::AuthScope::READ_ONLY
  end
end
