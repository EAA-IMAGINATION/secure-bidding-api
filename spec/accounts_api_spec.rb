# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'json'
require 'cgi'
require_relative '../app/require_app'

# rubocop:disable Metrics/BlockLength
describe 'API /api/v1/accounts' do
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
  end

  it 'HAPPY: creates an account with POST /api/v1/accounts' do
    payload = {
      username: 'route-alice',
      password: 'my-secret-pass',
      email: 'route-alice@example.com',
      phone: '+886900000001',
      system_role: 'member'
    }

    post '/api/v1/accounts', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 201
    response_body = JSON.parse(last_response.body)
    _(response_body['id']).wont_be_nil
    _(response_body['status']).must_equal 'created'

    stored = SecureBidding::Account[response_body['id']]
    _(stored).wont_be_nil
    _(stored.password_hash).wont_equal payload[:password]
  end

  it 'HAPPY: gets account metadata with GET /api/v1/accounts/:id' do
    account = SecureBidding::Account.new(username: 'route-bob', system_role: 'admin')
    account.set_password('my-secret-pass')
    account.set_email('route-bob@example.com')
    account.set_phone('+886900000002')
    account.save

    get "/api/v1/accounts/#{account.id}"

    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['id']).must_equal account.id
    _(response_body['username']).must_equal 'route-bob'
    _(response_body['system_role']).must_equal 'admin'
    _(response_body['email']).must_equal 'route-bob@example.com'
    _(response_body['phone']).must_equal '+886900000002'
    _(response_body.key?('password_hash')).must_equal false
    _(response_body.key?('password_salt')).must_equal false
    _(response_body.key?('email_secure')).must_equal false
  end

  it 'HAPPY: lists accounts with GET /api/v1/accounts' do
    account = SecureBidding::Account.new(username: 'list-user', system_role: 'member')
    account.set_password('my-secret-pass')
    account.set_email('list-user@example.com')
    account.save

    get '/api/v1/accounts'

    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['accounts']).must_be_kind_of Array
    _(response_body['accounts'].length).must_equal 1
    _(response_body['accounts'][0]['id']).must_equal account.id
    _(response_body['accounts'][0]['username']).must_equal 'list-user'
  end

  it 'HAPPY: searches accounts by email on GET /api/v1/accounts/search' do
    account = SecureBidding::Account.new(username: 'search-email-user', system_role: 'member')
    account.set_password('my-secret-pass')
    account.set_email('search-email@example.com')
    account.save

    get "/api/v1/accounts/search?email=#{CGI.escape('search-email@example.com')}"

    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['accounts']).must_be_kind_of Array
    _(response_body['accounts'].length).must_equal 1
    _(response_body['accounts'][0]['id']).must_equal account.id
    _(response_body['accounts'][0]['username']).must_equal 'search-email-user'
  end

  it 'SAD: rejects account creation with missing required fields' do
    post '/api/v1/accounts',
         { username: 'missing-password' }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'username, password, and email are required'
  end

  it 'SAD: rejects account creation with invalid system_role' do
    payload = {
      username: 'bad-role-user',
      password: 'my-secret-pass',
      email: 'bad-role@example.com',
      system_role: 'super-admin'
    }

    post '/api/v1/accounts', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'system_role must be admin or member'
  end

  it 'SAD: returns 404 for missing account id' do
    get '/api/v1/accounts/00000000-0000-0000-0000-000000000000'

    _(last_response.status).must_equal 404
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'Account not found'
  end

  it 'SAD: rejects search without email or phone criteria' do
    get '/api/v1/accounts/search'

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'email or phone query parameter is required'
  end

  it 'HAPPY: updates account fields with PATCH /api/v1/accounts/:id' do
    account = SecureBidding::Account.new(username: 'updatable-user', system_role: 'member')
    account.set_password('my-secret-pass')
    account.set_email('updatable-user@example.com')
    account.save

    patch "/api/v1/accounts/#{account.id}",
          { phone: '+886911222333', system_role: 'admin' }.to_json,
          { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['id']).must_equal account.id
    _(response_body['status']).must_equal 'updated'

    updated = SecureBidding::Account[account.id]
    _(updated.system_role).must_equal 'admin'
    _(updated.phone).must_equal '+886911222333'
  end

  it 'SAD: rejects account update without updatable fields' do
    account = SecureBidding::Account.new(username: 'no-update-user', system_role: 'member')
    account.set_password('my-secret-pass')
    account.set_email('no-update-user@example.com')
    account.save

    patch "/api/v1/accounts/#{account.id}", {}.to_json, { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'At least one updatable field is required'
  end

  it 'SAD: blocks mass assignment keys for account creation' do
    payload = {
      id: 'forced-id',
      username: 'forced-id-user',
      password: 'my-secret-pass',
      email: 'forced-id@example.com',
      system_role: 'member'
    }

    post '/api/v1/accounts', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'Invalid account attributes'
  end
end
# rubocop:enable Metrics/BlockLength
