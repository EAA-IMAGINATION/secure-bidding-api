# frozen_string_literal: true

require_relative 'spec_helper'
require 'net/smtp'
require 'uri'

# rubocop:disable Metrics/BlockLength
describe 'Demo lifecycle from registration to closed project' do
  include Rack::Test::Methods

  class LifecycleFakeSMTP
    attr_reader :messages

    def initialize
      @messages = []
    end

    def enable_starttls_auto; end

    def start(_domain, _username, _password, _auth)
      yield self
    end

    def send_message(message, from, to)
      @messages << { message: message, from: from, to: to }
    end
  end

  def app
    SecureBidding::App.freeze.app
  end

  def auth_header_for(account)
    token = SecureBidding::AuthToken.tokenize(
      { account_id: account.id, username: account.username, system_role: account.system_role },
      SecureBidding::AuthToken::ONE_HOUR
    )
    { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
  end

  def extract_registration_token(message)
    match = message.match(%r{register/verify/([^"&\s<]+)}) ||
            message.match(/token=([^"&\s<]+)/)
    return nil unless match

    URI.decode_www_form_component(match[1])
  end

  def register_and_verify(username:, email:, password: 'demo-pass-123')
    signed_post '/api/v1/auth/register', { username: username, email: email }
    _(last_response.status).must_equal 200

    token = extract_registration_token(@fake_smtp.messages.last[:message])
    _(token).wont_be_nil

    signed_post '/api/v1/auth/verify', { registration_token: token, password: password }
    _(last_response.status).must_equal 200

    body = JSON.parse(last_response.body)
    SecureBidding::Account[body['account']['id']]
  end

  def with_mailer_env
    original = {
      'MAILERTOGO_URL' => ENV['MAILERTOGO_URL'],
      'MAILERTOGO_FROM_EMAIL' => ENV['MAILERTOGO_FROM_EMAIL'],
      'MAILERTOGO_FROM_NAME' => ENV['MAILERTOGO_FROM_NAME']
    }
    ENV['MAILERTOGO_URL'] =
      'smtp://mailertogo-user:mailertogo-password@smtp.us-west-1.mailertogo.net:587?authentication=plain'
    ENV['MAILERTOGO_FROM_EMAIL'] = 'securebidfreelanceprocurementh@gmail.com'
    ENV['MAILERTOGO_FROM_NAME'] = 'Secure Bidding API'
    yield
  ensure
    original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  before do
    SecureBidding::AuthToken.setup(SecureBidding::AuthToken.generate_key)
    SecureBidding::Database.migrate!
    SecureBidding::BidSubmission.dataset.delete
    SecureBidding::Project.dataset.delete
    SecureBidding::AccountProject.dataset.delete
    SecureBidding::Account.dataset.delete

    @fake_smtp = LifecycleFakeSMTP.new
    @original_smtp_new = Net::SMTP.method(:new)
    fake_smtp = @fake_smtp
    Net::SMTP.define_singleton_method(:new) { |_host, _port| fake_smtp }
  end

  after do
    Net::SMTP.define_singleton_method(:new, @original_smtp_new)
  end

  it 'covers registration, admin promotion, required documents, sealed bids, award, and payment close' do
    with_mailer_env do
      owner = register_and_verify(username: 'demo-owner', email: 'demo-owner@example.com')
      bidder = register_and_verify(username: 'demo-bidder', email: 'demo-bidder@example.com')
      promote_target = register_and_verify(username: 'promote-me', email: 'promote-me@example.com')

      admin = SecureBidding::Account.new(username: 'demo-admin', system_role: 'admin')
      admin.set_password('admin-pass-123')
      admin.set_email('demo-admin@example.com')
      admin.save

      post "/api/v1/accounts/#{promote_target.id}/system_roles",
           { role: 'admin' }.to_json,
           auth_header_for(admin)
      _(last_response.status).must_equal 201
      _(SecureBidding::Account[promote_target.id].system_role).must_equal 'admin'

      deadline = Time.now + 1800
      post '/api/v1/projects',
           {
             title: 'Demo lifecycle project',
             description: 'End-to-end procurement demo',
             required_documents: ['Technical proposal', 'Pricing sheet'],
             budget_cents: 120_000,
             state: 'published',
             bidding_deadline: deadline.iso8601
           }.to_json,
           auth_header_for(owner)
      _(last_response.status).must_equal 201
      project_id = JSON.parse(last_response.body)['id']

      get "/api/v1/projects/#{project_id}", '', auth_header_for(owner)
      project_body = JSON.parse(last_response.body)
      _(project_body['required_documents']).must_equal ['Technical proposal', 'Pricing sheet']

      post "/api/v1/projects/#{project_id}/bids",
           {
             bidder_account_id: bidder.id,
             contractor_alias: 'demo-bidder',
             encrypted_document: sample_client_envelope('documents-bundle'),
             document_file_name: 'technical.pdf, pricing.pdf',
             document_file_hash: 'Technical proposal:hash-one|Pricing sheet:hash-two'
           }.merge(sample_client_bid_payload('95000')).to_json,
           auth_header_for(bidder)
      _(last_response.status).must_equal 201
      bid_submission_id = JSON.parse(last_response.body)['id']

      get "/api/v1/projects/#{project_id}/bid_count", '', auth_header_for(owner)
      _(last_response.status).must_equal 200
      _(JSON.parse(last_response.body)['bid_count']).must_equal 1

      get "/api/v1/projects/#{project_id}/bid_submissions", '', auth_header_for(owner)
      _(last_response.status).must_equal 404

      SecureBidding::Project[project_id].update(bidding_deadline: Time.now - 60)

      get "/api/v1/projects/#{project_id}/bid_submissions", '', auth_header_for(owner)
      _(last_response.status).must_equal 200
      bids_body = JSON.parse(last_response.body)
      _(bids_body['bid_submissions'].length).must_equal 1
      _(bids_body['bid_submissions'][0]['id']).must_equal bid_submission_id

      post "/api/v1/projects/#{project_id}/award",
           { bid_submission_id: bid_submission_id, awarded_bid_amount_cents: 95_000 }.to_json,
           auth_header_for(owner)
      _(last_response.status).must_equal 200
      _(JSON.parse(last_response.body)['state']).must_equal 'in_progress'

      post "/api/v1/projects/#{project_id}/request_payment", {}.to_json, auth_header_for(bidder)
      _(last_response.status).must_equal 200
      _(JSON.parse(last_response.body)['state']).must_equal 'payment_pending'

      post "/api/v1/projects/#{project_id}/process_payment", {}.to_json, auth_header_for(owner)
      _(last_response.status).must_equal 200
      _(JSON.parse(last_response.body)['payment_status']).must_equal 'in_process'

      post "/api/v1/projects/#{project_id}/acknowledge_payment", {}.to_json, auth_header_for(bidder)
      _(last_response.status).must_equal 200
      closed_body = JSON.parse(last_response.body)
      _(closed_body['state']).must_equal 'closed'
      _(closed_body['payment_status']).must_equal 'acknowledged'
      _(closed_body['payment_amount_cents']).must_equal 95_000
    end
  end
end
# rubocop:enable Metrics/BlockLength
