# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'json'
require_relative '../app/require_app'

describe 'API /api/v1/secrets' do
  include Rack::Test::Methods

  def app
    SecureBidding::App.freeze.app
  end

  before do
    SecureBidding::Database.migrate!
    SecureBidding::Secret.dataset.delete
    SecureBidding::Account.dataset.delete
  end

  it 'HAPPY: returns all secrets metadata from GET /api/v1/secrets' do
    account = SecureBidding::Account.create(username: 'list-user', email: 'list-user@example.com')
    secret = SecureBidding::Secret.new(account_id: account.id, title: 'api-key')
    secret.encrypt_data('key-1', 'c' * 32)
    secret.save

    get '/api/v1/secrets'

    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['secrets']).must_be_kind_of Array
    _(response_body['secrets'].length).must_equal 1
    _(response_body['secrets'][0]['id']).must_equal secret.id
    _(response_body['secrets'][0]['account_id']).must_equal account.id
    _(response_body['secrets'][0].key?('encrypted_data')).must_equal false
  end

  it 'HAPPY: returns 201 and stores encrypted data for valid payload' do
    account = SecureBidding::Account.create(username: 'route-user', email: 'route-user@example.com')
    payload = {
      account_id: account.id,
      title: 'db-password',
      plaintext: 'p@ssw0rd',
      key: 'a' * 32
    }

    post '/api/v1/secrets', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 201
    response_body = JSON.parse(last_response.body)
    _(response_body['id']).wont_be_nil
    _(response_body['status']).must_equal 'created'

    stored = SecureBidding::Secret[response_body['id']]
    _(stored).wont_be_nil
    _(stored.encrypted_data).wont_equal payload[:plaintext]
  end

  it 'SAD: returns 400 for invalid payload' do
    post '/api/v1/secrets', { title: 'missing owner' }.to_json, { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'account_id, title, plaintext, and key are required'
  end

  it 'HAPPY: returns secret metadata for an existing id' do
    account = SecureBidding::Account.create(username: 'meta-user', email: 'meta-user@example.com')
    secret = SecureBidding::Secret.new(account_id: account.id, title: 'api-token')
    secret.encrypt_data('token-123', 'b' * 32)
    secret.save

    get "/api/v1/secrets/#{secret.id}"

    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['id']).must_equal secret.id
    _(response_body['account_id']).must_equal account.id
    _(response_body['title']).must_equal 'api-token'
    _(response_body.key?('encrypted_data')).must_equal false
  end

  it 'SAD: returns 404 for missing secret id' do
    get '/api/v1/secrets/999999'

    _(last_response.status).must_equal 404
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'Secret not found'
  end
end
