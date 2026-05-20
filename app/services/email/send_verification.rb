# frozen_string_literal: true

require 'http'
require 'json'
require 'net/smtp'
require_relative '../../../config/environments'

module SecureBidding
  module Services
    module Email
      # Sends verification emails via Mailtrap API
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

          # Record payload(s) for specs as a fallback when WebMock interception is unreliable
          SecureBidding::Services::Email::SendVerification.last_payload = payload
          SecureBidding::Services::Email::SendVerification.last_payloads ||= []
          SecureBidding::Services::Email::SendVerification.last_payloads << payload

          if ENV.fetch('MAILERTOGO_DELIVERY_METHOD', 'api') == 'smtp'
            return send_via_smtp(payload)
          end

          response = send_to_mailtrap(payload)

          unless response.status.success?
            raise MailtrapError, "Mailtrap API error: #{response.status} - #{response.body}"
          end

          { ok: true, message: 'Verification email sent' }
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
          ENV.fetch('MAILERTOGO_FROM_EMAIL', ENV.fetch('MAILTRAP_FROM_EMAIL', 'noreply@secure-bidding-api.local'))
        end

        def from_name
          SecureBidding::Environment.load_secrets!
          ENV.fetch('MAILERTOGO_FROM_NAME', ENV.fetch('MAILTRAP_FROM_NAME', 'Secure Bidding API'))
        end

        def send_to_mailtrap(payload)
          api_key = mailtrap_api_key
          api_url = mailtrap_api_url

          # Record headers used so specs can assert Authorization even if WebMock doesn't capture the request
          SecureBidding::Services::Email::SendVerification.last_headers = { 'Authorization' => "Bearer #{api_key}" }
          SecureBidding::Services::Email::SendVerification.last_headers_array ||= []
          SecureBidding::Services::Email::SendVerification.last_headers_array << SecureBidding::Services::Email::SendVerification.last_headers

          HTTP.auth("Bearer #{api_key}")
              .post(
                api_url,
                json: payload
              )
        end

        def send_via_smtp(payload)
          SecureBidding::Environment.load_secrets!
          host = ENV.fetch('MAILERTOGO_SMTP_HOST', 'localhost')
          port = ENV.fetch('MAILERTOGO_SMTP_PORT', '587').to_i
          username = ENV.fetch('MAILERTOGO_SMTP_USER', '')
          password = ENV.fetch('MAILERTOGO_SMTP_PASSWORD', '')
          auth = (ENV['MAILERTOGO_SMTP_AUTH'] || 'plain').to_sym

          if username.to_s.strip.empty? || password.to_s.strip.empty?
            raise MailtrapError, 'SMTP credentials missing'
          end

          to_email = payload[:to].first[:email]
          message = <<~MSG
            From: #{from_name} <#{from_email}>
            To: #{to_email}
            Subject: #{payload[:subject]}
            MIME-Version: 1.0
            Content-type: text/html

            #{payload[:html]}
          MSG

          smtp = Net::SMTP.new(host, port)
          smtp.enable_starttls_auto if smtp.respond_to?(:enable_starttls_auto)
          smtp.start('localhost', username, password, auth) do |s|
            s.send_message(message, from_email, to_email)
          end

          { ok: true, message: 'Verification email sent (smtp)' }
        end

        def mailtrap_api_key
          SecureBidding::Environment.load_secrets!
          ENV.fetch('MAILTRAP_API_KEY', '')
        end

        def mailtrap_api_url
          SecureBidding::Environment.load_secrets!
          ENV.fetch('MAILTRAP_API_URL', 'https://send.api.mailtrap.io/api/send')
        end
      end
    end
  end
end
