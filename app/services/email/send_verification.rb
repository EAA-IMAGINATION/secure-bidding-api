# frozen_string_literal: true

require 'erb'
require 'json'
require 'net/smtp'
require 'uri'
require_relative '../../../config/environments'

module SecureBidding
  module Services
    module Email
      # Sends verification emails via Mailer To Go SMTP
      class SendVerification
        class MailerToGoError < StandardError; end

        class << self
          attr_accessor :last_payload, :last_payloads
        end

        def self.call(account:, verification_link:, purpose: :registration)
          new(account, verification_link, purpose).send_verification_email
        end

        def initialize(account, verification_link, purpose)
          @account = account
          @verification_link = verification_link
          @purpose = purpose
        end

        def send_verification_email
          payload = build_payload

          # Record payload(s) for specs as a fallback when WebMock interception is unreliable
          SecureBidding::Services::Email::SendVerification.last_payload = payload
          SecureBidding::Services::Email::SendVerification.last_payloads ||= []
          SecureBidding::Services::Email::SendVerification.last_payloads << payload

          send_via_mailer_togo(payload)

          { ok: true, message: 'Verification email sent' }
        rescue StandardError => e
          raise MailerToGoError, "Failed to send verification email: #{e.message}"
        end

        private

        attr_reader :account, :verification_link, :purpose

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
            subject: email_subject,
            html: build_html_template
          }
        end

        def email_subject
          purpose == :registration ? 'Verify your registration' : 'Verify your email address'
        end

        def intro_text
          if purpose == :registration
            'Please verify your email address to complete your registration. Open the link below to continue.'
          else
            'Please verify your email address. Open the link below to confirm this change.'
          end
        end

        def build_html_template
          <<~HTML
            <!DOCTYPE html>
            <html>
              <head>
                <meta charset="UTF-8">
              </head>
              <body>
                <h2>Hello #{ERB::Util.html_escape(account.username)},</h2>
                <p>#{intro_text}</p>
                <p>
                  <a href="#{ERB::Util.html_escape(verification_link)}" style="display: inline-block; padding: 10px 20px; background-color: #0066cc; color: white; text-decoration: none; border-radius: 5px;">
                    Verify Email Address
                  </a>
                </p>
                <p>If the button above doesn't work, copy and paste this link into your browser:</p>
                <p>#{ERB::Util.html_escape(verification_link)}</p>
                <p>This link will expire in 1 hour.</p>
                <p>If you didn't request this, please ignore this email.</p>
              </body>
            </html>
          HTML
        end

        def from_email
          SecureBidding::Environment.load_secrets!
          ENV.fetch('MAILERTOGO_FROM_EMAIL', 'securebidfreelanceprocurementh@gmail.com')
        end

        def from_name
          SecureBidding::Environment.load_secrets!
          ENV.fetch('MAILERTOGO_FROM_NAME', 'Secure Bidding API')
        end

        def send_via_mailer_togo(payload)
          SecureBidding::Environment.load_secrets!
          settings = smtp_settings

          if settings[:username].to_s.strip.empty? || settings[:password].to_s.strip.empty?
            raise MailerToGoError, 'SMTP credentials missing'
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

          smtp = Net::SMTP.new(settings[:host], settings[:port])
          smtp.enable_starttls_auto if smtp.respond_to?(:enable_starttls_auto)
          smtp.start('localhost', settings[:username], settings[:password], settings[:auth]) do |s|
            s.send_message(message, from_email, to_email)
          end

          { ok: true, message: 'Verification email sent (smtp)' }
        end

        def smtp_settings
          if (mailertogo_url = ENV['MAILERTOGO_URL']).to_s.strip != ''
            uri = URI.parse(mailertogo_url)
            params = uri.query ? URI.decode_www_form(uri.query).to_h : {}

            {
              host: uri.host || ENV.fetch('MAILERTOGO_SMTP_HOST', 'localhost'),
              port: (uri.port || ENV.fetch('MAILERTOGO_SMTP_PORT', '587')).to_i,
              username: URI.decode_www_form_component(uri.user.to_s),
              password: URI.decode_www_form_component(uri.password.to_s),
              auth: (params['authentication'] || params['auth'] || 'plain').to_sym
            }
          else
            {
              host: ENV.fetch('MAILERTOGO_SMTP_HOST', 'localhost'),
              port: ENV.fetch('MAILERTOGO_SMTP_PORT', '587').to_i,
              username: ENV.fetch('MAILERTOGO_SMTP_USER', ''),
              password: ENV.fetch('MAILERTOGO_SMTP_PASSWORD', ''),
              auth: (ENV['MAILERTOGO_SMTP_AUTH'] || 'plain').to_sym
            }
          end
        end
      end
    end
  end
end
