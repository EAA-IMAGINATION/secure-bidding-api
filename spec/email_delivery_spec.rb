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

    def enable_tls
      @tls_enabled = true
    end

    def enable_starttls
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

  it 'reads lowercase Figaro mailer config keys' do
    fake_smtp = FakeSMTP.new
    account = OpenStruct.new(username: 'mailuser', email: 'recipient@example.com')

    with_mailer_togo_env(
      'MAILERTOGO_URL' => nil,
      'mailertogo_url' => 'smtp://mailertogo-user:mailertogo-password@smtp.us-west-1.mailertogo.net:587?authentication=plain',
      'MAILERTOGO_SMTP_HOST' => nil,
      'mailertogo_smtp_host' => 'smtp.us-west-1.mailertogo.net',
      'MAILERTOGO_SMTP_USER' => nil,
      'mailertogo_smtp_user' => 'mailertogo-user',
      'MAILERTOGO_SMTP_PASSWORD' => nil,
      'mailertogo_smtp_password' => 'mailertogo-password',
      'MAILERTOGO_FROM_EMAIL' => nil,
      'mailertogo_from_email' => 'noreply@freelanceprocurementhub.tech',
      'MAILERTOGO_FROM_NAME' => nil,
      'mailertogo_from_name' => 'Secure Bidding API',
      'MAILERTOGO_SMTP_DOMAIN' => nil,
      'mailertogo_smtp_domain' => 'freelanceprocurementhub.tech'
    ) do
      with_smtp_stub(fake_smtp) do
        result = SecureBidding::Services::Email::SendVerification.call(
          account: account,
          verification_link: 'https://example.test/verify-email?token=token-123',
          purpose: :registration
        )

        _(result[:ok]).must_equal true
        _(fake_smtp.started_with[:domain]).must_equal 'freelanceprocurementhub.tech'
      end
    end
  end

  it 'uses implicit TLS for Titan SMTP on port 465' do
    fake_smtp = FakeSMTP.new
    account = OpenStruct.new(username: 'mailuser', email: 'recipient@example.com')

    with_mailer_togo_env(
      'MAILERTOGO_URL' => nil,
      'mailertogo_url' => nil,
      'MAILERTOGO_SMTP_HOST' => 'smtp.titan.email',
      'MAILERTOGO_SMTP_PORT' => '465',
      'MAILERTOGO_SMTP_USER' => 'noreply@freelanceprocurementhub.tech',
      'MAILERTOGO_SMTP_PASSWORD' => 'titan-mailbox-password',
      'MAILERTOGO_SMTP_AUTH' => 'plain',
      'MAILERTOGO_FROM_EMAIL' => 'noreply@freelanceprocurementhub.tech',
      'MAILERTOGO_FROM_NAME' => 'Freelance Procurement Hub',
      'MAILERTOGO_SMTP_DOMAIN' => 'freelanceprocurementhub.tech'
    ) do
      with_smtp_stub(fake_smtp) do
        result = SecureBidding::Services::Email::SendVerification.call(
          account: account,
          verification_link: 'https://example.test/verify-email?token=token-123',
          purpose: :registration
        )

        _(result[:ok]).must_equal true
        _(fake_smtp.instance_variable_get(:@tls_enabled)).must_equal true
        _(fake_smtp.started_with[:username]).must_equal 'noreply@freelanceprocurementhub.tech'
      end
    end
  end

  it 'uses Mailer To Go SMTP credentials when they are configured' do
    fake_smtp = FakeSMTP.new
    account = OpenStruct.new(username: 'mailuser', email: 'recipient@example.com')

    with_mailer_togo_env(
      'MAILERTOGO_URL' => nil,
      'mailertogo_url' => nil,
      'MAILERTOGO_SMTP_HOST' => 'smtp.us-west-1.mailertogo.net',
      'MAILERTOGO_SMTP_PORT' => '587',
      'MAILERTOGO_SMTP_USER' => 'mailertogo-user',
      'MAILERTOGO_SMTP_PASSWORD' => 'mailertogo-password',
      'MAILERTOGO_SMTP_AUTH' => 'plain',
      'MAILERTOGO_FROM_EMAIL' => 'noreply@freelanceprocurementhub.tech',
      'MAILERTOGO_FROM_NAME' => 'Secure Bidding API',
      'MAILERTOGO_SMTP_DOMAIN' => 'freelanceprocurementhub.tech'
    ) do
      with_smtp_stub(fake_smtp) do
        result = SecureBidding::Services::Email::SendVerification.call(
          account: account,
          verification_link: 'https://example.test/verify-email?token=token-123',
          purpose: :registration
        )

        _(result[:ok]).must_equal true
        _(fake_smtp.started_with[:domain]).must_equal 'freelanceprocurementhub.tech'
        _(fake_smtp.started_with[:username]).must_equal 'mailertogo-user'
        _(fake_smtp.started_with[:password]).must_equal 'mailertogo-password'
        _(fake_smtp.started_with[:auth]).must_equal :plain
        _(fake_smtp.messages.length).must_equal 1
        message = fake_smtp.messages.first
        _(message[:from]).must_equal 'noreply@freelanceprocurementhub.tech'
        _(message[:to]).must_equal 'recipient@example.com'
        _(message[:message]).must_include 'Verify your registration'
      end
    end
  end

  it 'raises an error when SMTP credentials are missing' do
    account = OpenStruct.new(username: 'mailuser', email: 'recipient@example.com')

    with_mailer_togo_env(
      'MAILERTOGO_URL' => nil,
      'mailertogo_url' => nil,
      'MAILERTOGO_SMTP_HOST' => 'smtp.us-west-1.mailertogo.net',
      'MAILERTOGO_SMTP_PORT' => '587',
      'MAILERTOGO_SMTP_USER' => 'mailertogo-user',
      'mailertogo_smtp_user' => 'mailertogo-user',
      'MAILERTOGO_SMTP_PASSWORD' => '',
      'mailertogo_smtp_password' => ''
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
