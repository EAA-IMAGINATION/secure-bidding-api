# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'net/smtp'
require 'rack/test'
require 'uri'
require_relative 'spec_helper'

describe 'Mailer To Go SMTP integration' do
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
      @messages << { message: message, from: from, to: to }
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
    ENV['MAILERTOGO_FROM_EMAIL'] = 'noreply@freelanceprocurementhub.tech'
    ENV['MAILERTOGO_FROM_NAME'] = 'Secure Bidding API'
    ENV['MAILERTOGO_SMTP_DOMAIN'] = 'freelanceprocurementhub.tech'
    yield
  ensure
    original.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  def extract_registration_token(message)
    match = message.match(/token=([^"&\s<]+)/)
    match && URI.decode_www_form_component(match[1])
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

  it 'sends a verification email through SMTP' do
    with_mailer_togo_env do
      signed_post '/api/v1/auth/register',
           { username: 'emailtest1', email: 'emailtest1@example.com' }
    end

    _(last_response.status).must_equal 200
    _( @fake_smtp.messages.length).must_equal 1
    payload = @fake_smtp.messages.first[:message]
    _(payload).must_include 'Verify your registration'
    _(payload).must_include 'emailtest1@example.com'
  end

  it 'renders the verification token in the email body' do
    with_mailer_togo_env do
      signed_post '/api/v1/auth/register',
           { username: 'tokentest', email: 'tokentest@example.com' }
    end

    payload = @fake_smtp.messages.first[:message]
    token = extract_registration_token(payload)
    token_payload = SecureBidding::AuthToken.load(token).payload

    _(payload).must_include 'token='
    _(token_payload[:username]).must_equal 'tokentest'
    _(token_payload[:email]).must_equal 'tokentest@example.com'
  end
end
