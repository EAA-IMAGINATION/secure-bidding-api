# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'ostruct'
require 'net/smtp'
require_relative '../app/require_app'

describe 'Mailer To Go SMTP delivery' do
  class FakeSMTP
    attr_reader :started_with, :messages

    def initialize
      @messages = []
    end

    def enable_starttls_auto
      @starttls_enabled = true
    end

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

  def with_mailer_togo_env(env)
    keys = env.keys
    original = keys.to_h { |key| [key, ENV.key?(key) ? ENV[key] : :__missing__] }
    env.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
    yield
  ensure
    original.each do |key, value|
      value == :__missing__ ? ENV.delete(key) : ENV[key] = value
    end
  end

  def with_smtp_stub(fake_smtp)
    original_new = nil
    original_new = Net::SMTP.method(:new)
    Net::SMTP.define_singleton_method(:new) do |_host, _port|
      fake_smtp
    end
    yield
  ensure
    Net::SMTP.define_singleton_method(:new, &original_new.to_proc) if original_new
  end

  it 'uses Mailer To Go SMTP credentials when they are configured' do
    fake_smtp = FakeSMTP.new
    account = OpenStruct.new(username: 'mailuser', email: 'recipient@example.com')

    with_mailer_togo_env(
      'MAILERTOGO_URL' => nil,
      'MAILERTOGO_SMTP_HOST' => 'smtp.us-west-1.mailertogo.net',
      'MAILERTOGO_SMTP_PORT' => '587',
      'MAILERTOGO_SMTP_USER' => 'mailertogo-user',
      'MAILERTOGO_SMTP_PASSWORD' => 'mailertogo-password',
      'MAILERTOGO_SMTP_AUTH' => 'plain',
      'MAILERTOGO_FROM_EMAIL' => 'securebidfreelanceprocurementh@gmail.com',
      'MAILERTOGO_FROM_NAME' => 'Secure Bidding API'
    ) do
      with_smtp_stub(fake_smtp) do
        result = SecureBidding::Services::Email::SendVerification.call(
          account: account,
          verification_link: 'https://example.test/verify-email?token=token-123',
          purpose: :registration
        )

        _(result[:ok]).must_equal true
        _(fake_smtp.started_with[:domain]).must_equal 'localhost'
        _(fake_smtp.started_with[:username]).must_equal 'mailertogo-user'
        _(fake_smtp.started_with[:password]).must_equal 'mailertogo-password'
        _(fake_smtp.started_with[:auth]).must_equal :plain
        _(fake_smtp.messages.length).must_equal 1
        message = fake_smtp.messages.first
        _(message[:from]).must_equal 'securebidfreelanceprocurementh@gmail.com'
        _(message[:to]).must_equal 'recipient@example.com'
        _(message[:message]).must_include 'Verify your registration'
      end
    end
  end

  it 'raises an error when SMTP credentials are missing' do
    account = OpenStruct.new(username: 'mailuser', email: 'recipient@example.com')

    with_mailer_togo_env(
      'MAILERTOGO_URL' => nil,
      'MAILERTOGO_SMTP_HOST' => 'smtp.us-west-1.mailertogo.net',
      'MAILERTOGO_SMTP_PORT' => '587',
      'MAILERTOGO_SMTP_USER' => 'mailertogo-user',
      'MAILERTOGO_SMTP_PASSWORD' => ''
    ) do
      error = assert_raises(SecureBidding::Services::Email::SendVerification::MailerToGoError) do
        SecureBidding::Services::Email::SendVerification.call(
          account: account,
          verification_link: 'https://example.test/verify-email?token=token-123',
          purpose: :registration
        )
      end

      _(error.message).must_include 'SMTP'
    end
  end
end
