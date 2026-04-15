# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'json'
require_relative '../app/require_app'

describe 'API /api/v1/accounts' do
  include Rack::Test::Methods

  def app
    SecureBidding::App.freeze.app
  end

  before do
    SecureBidding::Database.migrate!
    SecureBidding::Secret.dataset.delete
    SecureBidding::Account.dataset.delete
  end

  it 'HAPPY: creates an account with POST /api/v1/accounts' do
    post '/api/v1/accounts',
         { username: 'acc-user', email: 'acc@example.com' }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 201
    response_body = JSON.parse(last_response.body)
    _(response_body['id']).wont_be_nil
    _(response_body['status']).must_equal 'created'
  end

  it 'HAPPY: lists accounts with GET /api/v1/accounts' do
    SecureBidding::Account.create(username: 'a1', email: 'a1@example.com')
    SecureBidding::Account.create(username: 'a2', email: 'a2@example.com')

    get '/api/v1/accounts'

    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['accounts']).must_be_kind_of Array
    _(response_body['accounts'].length).must_equal 2
  end

  it 'HAPPY: fetches a single account with GET /api/v1/accounts/:id' do
    account = SecureBidding::Account.create(username: 'single', email: 'single@example.com')

    get "/api/v1/accounts/#{account.id}"

    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['id']).must_equal account.id
    _(response_body['username']).must_equal 'single'
    _(response_body['email']).must_equal 'single@example.com'
  end

  it 'SAD: rejects invalid account payload' do
    post '/api/v1/accounts', { username: '' }.to_json, { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'username and email are required'
  end

  it 'SAD: returns 404 for unknown account id' do
    get '/api/v1/accounts/999999'

    _(last_response.status).must_equal 404
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'Account not found'
  end
end
