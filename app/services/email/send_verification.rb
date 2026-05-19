# frozen_string_literal: true

require 'erb'
require 'http'
require 'json'
require 'net/smtp'
require 'uri'
require_relative '../../../config/environments'

module SecureBidding
  module Services
    module Email
      # Sends verification emails through Mailer To Go SMTP when configured.
      # Falls back to the legacy Mailtrap API path for test compatibility.
      class SendVerification
        class MailtrapError < StandardError; end

        class << self
          attr_accessor :last_payload, :last_headers, :last_payloads, :last_headers_array
        end

        def self.call(account:, registration_token:, verification_url:)
          new(account, registration_token, verification_url).send_verification_email
        end

        def initialize(account, registration_token, verification_url)
          @account = account
          @registration_token = registration_token
          @verification_url = verification_url
        end

        def send_verification_email
          payload = build_payload

          SecureBidding::Services::Email::SendVerification.last_payload = payload
          SecureBidding::Services::Email::SendVerification.last_payloads ||= []
          SecureBidding::Services::Email::SendVerification.last_payloads << payload

          if mailer_togo_smtp?
            send_to_smtp(payload)
          else
            response = send_to_mailtrap(payload)
            unless response.status.success?
              raise MailtrapError, "Mailtrap API error: #{response.status} - #{response.body}"
            end
          end

          { ok: true, message: 'Verification email sent' }
        rescue MailtrapError
          raise
        rescue StandardError => e
          raise MailtrapError, "Failed to send verification email: #{e.message}"
        end

        private

        attr_reader :account, :registration_token, :verification_url

        def build_payload
          {
            from: {
              email: from_email,
              name: from_name
            },
            to: [
              {
                email: account.email
              }
            ],
            subject: 'Verify your registration',
            html: build_html_template
          }
        end

        def build_html_template
          verification_link = "#{verification_url}?token=#{registration_token}"

          <<~HTML
            <!DOCTYPE html>
            <html>
              <head>
                <meta charset="UTF-8">
              </head>
              <body>
                <h2>Welcome to Secure Bidding API, #{ERB::Util.html_escape(account.username)}!</h2>
                <p>Please verify your email address to complete your registration. This email contains your verification link.</p>
                <p>
                  <a href="#{ERB::Util.html_escape(verification_link)}" style="display: inline-block; padding: 10px 20px; background-color: #0066cc; color: white; text-decoration: none; border-radius: 5px;">
                    Verify Email Address
                  </a>
                </p>
                <p>If the button above doesn't work, copy and paste this link into your browser:</p>
                <p>#{ERB::Util.html_escape(verification_link)}</p>
                <p>This link will expire in 1 hour.</p>
                <p>If you didn't create this account, please ignore this email.</p>
              </body>
            </html>
          HTML
        end

        def from_email
          SecureBidding::Environment.load_secrets!
          ENV.fetch('MAILERTOGO_FROM_EMAIL',
                    ENV.fetch('MAILTRAP_FROM_EMAIL', 'noreply@secure-bidding-api.local'))
        end

        def from_name
          SecureBidding::Environment.load_secrets!
          ENV.fetch('MAILERTOGO_FROM_NAME',
                    ENV.fetch('MAILTRAP_FROM_NAME', 'Secure Bidding API'))
        end

        def send_to_mailtrap(payload)
          api_key = mailtrap_api_key
          api_url = mailtrap_api_url

          SecureBidding::Services::Email::SendVerification.last_headers = { 'Authorization' => "Bearer #{api_key}" }
          SecureBidding::Services::Email::SendVerification.last_headers_array ||= []
          SecureBidding::Services::Email::SendVerification.last_headers_array << SecureBidding::Services::Email::SendVerification.last_headers

          HTTP.auth("Bearer #{api_key}")
              .post(
                api_url,
                json: payload
              )
        end

        def send_to_smtp(payload)
          validate_smtp_settings!

          smtp = Net::SMTP.new(smtp_host, smtp_port)
          smtp.enable_starttls_auto if smtp_starttls?
          smtp.start(smtp_domain, smtp_username, smtp_password, smtp_auth_method) do |client|
            client.send_message(smtp_message(payload), from_email, account.email)
          end
        end

        def mailer_togo_smtp?
          SecureBidding::Environment.load_secrets!
          delivery_method = ENV.fetch('MAILERTOGO_DELIVERY_METHOD', '').to_s.strip.downcase
          return true if delivery_method == 'smtp'

          mailer_togo_smtp_configured?
        end

        def mailer_togo_smtp_configured?
          smtp_url_present? || (mailer_togo_username_present? && mailer_togo_password_present?)
        end

        def smtp_url_present?
          url = smtp_url
          return false if url.nil?
          return false if placeholder_value?(url.host)
          return false if placeholder_value?(url.user)
          return false if placeholder_value?(url.password)

          true
        end

        def mailtrap_api_key
          SecureBidding::Environment.load_secrets!
          token = ENV.fetch('MAILTRAP_API_TOKEN', '').to_s.strip
          token = ENV.fetch('MAILTRAP_API_KEY', '').to_s.strip if token.empty?
          return 'test-mailtrap-token' if invalid_mailtrap_token?(token) && SecureBidding::Environment.app_env == 'test'
          raise MailtrapError, 'Mailtrap API token is missing' if invalid_mailtrap_token?(token)

          token
        end

        def mailtrap_api_url
          SecureBidding::Environment.load_secrets!
          ENV.fetch('MAILTRAP_API_URL', 'https://send.api.mailtrap.io/api/send')
        end

        def smtp_url
          SecureBidding::Environment.load_secrets!
          raw = ENV.fetch('MAILERTOGO_URL', '').to_s.strip
          return nil if raw.empty?

          URI.parse(raw)
        rescue URI::InvalidURIError
          nil
        end

        def smtp_host
          SecureBidding::Environment.load_secrets!
          ENV.fetch('MAILERTOGO_SMTP_HOST', smtp_url&.host || 'smtp.us-west-1.mailertogo.net')
        end

        def smtp_port
          SecureBidding::Environment.load_secrets!
          ENV.fetch('MAILERTOGO_SMTP_PORT', smtp_url&.port || '587').to_i
        end

        def smtp_username
          SecureBidding::Environment.load_secrets!
          ENV.fetch('MAILERTOGO_SMTP_USER',
                    smtp_url&.user || ENV.fetch('MAILTRAP_SMTP_USERNAME', ''))
        end

        def smtp_password
          SecureBidding::Environment.load_secrets!
          ENV.fetch('MAILERTOGO_SMTP_PASSWORD',
                    smtp_url&.password || ENV.fetch('MAILTRAP_SMTP_PASSWORD', ''))
        end

        def smtp_domain
          SecureBidding::Environment.load_secrets!
          ENV.fetch('MAILERTOGO_SMTP_DOMAIN', 'localhost')
        end

        def smtp_auth_method
          SecureBidding::Environment.load_secrets!
          auth = ENV.fetch('MAILERTOGO_SMTP_AUTH', '').to_s.strip
          auth = smtp_url_auth_method if auth.empty?
          auth = ENV.fetch('MAILTRAP_SMTP_AUTH', 'plain') if auth.to_s.strip.empty?
          auth.to_sym
        end

        def smtp_url_auth_method
          params = smtp_url&.query ? URI.decode_www_form(smtp_url.query).to_h : {}
          params['authentication'] || 'plain'
        end

        def smtp_starttls?
          SecureBidding::Environment.load_secrets!
          value = ENV.fetch('MAILERTOGO_SMTP_STARTTLS', ENV.fetch('MAILTRAP_SMTP_STARTTLS', 'true'))
          value.to_s.strip.downcase != 'false'
        end

        def smtp_message(payload)
          [
            "From: #{from_name} <#{from_email}>",
            "To: #{account.email}",
            "Subject: #{payload[:subject]}",
            'MIME-Version: 1.0',
            'Content-Type: text/html; charset=UTF-8',
            '',
            payload[:html].to_s
          ].join("\r\n")
        end

        def validate_smtp_settings!
          raise MailtrapError, 'Mailer To Go SMTP username is missing' if smtp_username.empty?
          raise MailtrapError, 'Mailer To Go SMTP password is missing' if smtp_password.empty?
        end

        def mailer_togo_username_present?
          value = smtp_username
          !value.empty? && !placeholder_value?(value)
        end

        def mailer_togo_password_present?
          value = smtp_password
          !value.empty? && !placeholder_value?(value)
        end

        def invalid_mailtrap_token?(token)
          token.empty? || token.match?(/\A<.*>\z/)
        end

        def placeholder_value?(value)
          value.to_s.match?(/\A<.*>\z/)
        end
      end
    end
  end
end
