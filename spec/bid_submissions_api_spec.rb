# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'json'
require 'cgi'
require_relative '../app/require_app'

describe 'API /api/v1/bid_submissions' do
  include Rack::Test::Methods

  def app
    SecureBidding::App.freeze.app
  end

  before do
    SecureBidding::Database.migrate!
    SecureBidding::BidSubmission.dataset.delete
    SecureBidding::Project.dataset.delete
  end

  it 'HAPPY: returns all bid submissions metadata from GET /api/v1/bid_submissions' do
    project = SecureBidding::Project.create(title: 'list-project', budget_cents: 120_000)
    bid_submission = SecureBidding::BidSubmission.new(project_id: project.id, contractor_alias: 'api-key-labs')
    bid_submission.encrypt_bid('payload-1')
    bid_submission.save

    get '/api/v1/bid_submissions'

    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['bid_submissions']).must_be_kind_of Array
    _(response_body['bid_submissions'].length).must_equal 1
    _(response_body['bid_submissions'][0]['id']).must_equal bid_submission.id
    _(response_body['bid_submissions'][0]['project_id']).must_equal project.id
    _(response_body['bid_submissions'][0]['contractor_alias']).must_equal 'api-key-labs'
    _(response_body['bid_submissions'][0].key?('secure_encrypted_bid')).must_equal false
  end

  it 'HAPPY: returns 201 and stores encrypted payload for valid payload' do
    project = SecureBidding::Project.create(title: 'route-project', budget_cents: 333_000)
    payload = {
      project_id: project.id,
      contractor_alias: 'route-user',
      plaintext_bid: 'p@ssw0rd'
    }

    post '/api/v1/bid_submissions', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 201
    response_body = JSON.parse(last_response.body)
    _(response_body['id']).wont_be_nil
    _(response_body['status']).must_equal 'created'

    stored = SecureBidding::BidSubmission[response_body['id']]
    _(stored).wont_be_nil
    _(stored.secure_encrypted_bid).wont_equal payload[:plaintext_bid]
  end

  it 'SAD: returns 400 for invalid payload' do
    post '/api/v1/bid_submissions',
         { contractor_alias: 'missing project' }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'project_id, contractor_alias, and plaintext_bid are required'
  end

  it 'HAPPY: returns bid submission metadata for an existing id' do
    project = SecureBidding::Project.create(title: 'meta-project', budget_cents: 10_000)
    bid_submission = SecureBidding::BidSubmission.new(project_id: project.id, contractor_alias: 'meta-user')
    bid_submission.encrypt_bid('token-123')
    bid_submission.save

    get "/api/v1/bid_submissions/#{bid_submission.id}"

    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['id']).must_equal bid_submission.id
    _(response_body['project_id']).must_equal project.id
    _(response_body['contractor_alias']).must_equal 'meta-user'
    _(response_body.key?('secure_encrypted_bid')).must_equal false
  end

  it 'SAD: returns 404 for missing bid submission id' do
    get '/api/v1/bid_submissions/00000000-0000-0000-0000-000000000000'

    _(last_response.status).must_equal 404
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'Bid submission not found'
  end

  it 'SAD: blocks mass assignment keys for bid submission creation' do
    project = SecureBidding::Project.create(title: 'locked-project', budget_cents: 45_000)
    payload = {
      project_id: project.id,
      contractor_alias: 'locked-user',
      plaintext_bid: 'p@ssw0rd',
      id: 'forced-id'
    }

    post '/api/v1/bid_submissions', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'Invalid bid submission attributes'
    _(SecureBidding::BidSubmission.count).must_equal 0
  end

  it 'SAD: rejects SQL injection string in project_id for bid submission creation' do
    payload = {
      project_id: "00000000-0000-0000-0000-000000000000' OR 1=1 --",
      contractor_alias: 'db-password',
      plaintext_bid: 'p@ssw0rd'
    }

    post '/api/v1/bid_submissions', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'project_id must be a UUID'
  end

  it 'SAD: rejects SQL injection string in bid submission id route' do
    get "/api/v1/bid_submissions/#{CGI.escape("00000000-0000-0000-0000-000000000000' OR 1=1 --")}"

    _(last_response.status).must_equal 404
  end
end
