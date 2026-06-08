# frozen_string_literal: true

require 'erb'
require 'json'
require 'net/smtp'
require 'uri'
require_relative '../../../config/environments'

module SecureBidding
  module Services
    module Email
      # Sends verification emails via SMTP (Mailer To Go, Titan, or other provider)
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

          send_via_smtp(payload)

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
          SecureBidding::Environment.env_value(
            'MAILERTOGO_FROM_EMAIL',
            'mailertogo_from_email',
            default: 'noreply@freelanceprocurementhub.tech'
          )
        end

        def from_name
          SecureBidding::Environment.env_value(
            'MAILERTOGO_FROM_NAME',
            'mailertogo_from_name',
            default: 'Secure Bidding API'
          )
        end

        def send_via_smtp(payload)
          SecureBidding::Environment.load_secrets!
          settings = smtp_settings

          if settings[:username].to_s.strip.empty? || settings[:password].to_s.strip.empty?
            raise MailerToGoError, 'SMTP credentials missing'
          end

          to_email = payload[:to].first[:email]
          message = build_smtp_message(payload)

          smtp = Net::SMTP.new(settings[:host], settings[:port])
          smtp.open_timeout = 30 if smtp.respond_to?(:open_timeout=)
          smtp.read_timeout = 30 if smtp.respond_to?(:read_timeout=)
          configure_smtp_tls(smtp, settings)
          smtp.start(smtp_helo_domain, settings[:username], settings[:password], settings[:auth]) do |s|
            s.send_message(message, from_email, to_email)
          end

          { ok: true, message: 'Verification email sent (smtp)' }
        end

        def configure_smtp_tls(smtp, settings)
          if settings[:tls]
            smtp.enable_tls if smtp.respond_to?(:enable_tls)
          elsif smtp.respond_to?(:enable_starttls)
            smtp.enable_starttls
          end
        end

        def build_smtp_message(payload)
          to_email = payload[:to].first[:email]
          [
            "From: #{from_name} <#{from_email}>",
            "To: #{to_email}",
            "Subject: #{payload[:subject]}",
            'MIME-Version: 1.0',
            'Content-Type: text/html; charset=UTF-8',
            '',
            payload[:html]
          ].join("\r\n") + "\r\n"
        end

        def smtp_helo_domain
          domain = SecureBidding::Environment.env_value(
            'MAILERTOGO_SMTP_DOMAIN',
            'mailertogo_smtp_domain',
            'MAILERTOGO_DOMAIN',
            'mailertogo_domain'
          ).to_s.strip
          return domain unless domain.empty?

          frontend = SecureBidding::Environment.env_value(
            'FRONTEND_APP_URL',
            'frontend_app_url',
            'APP_URL',
            'app_url'
          ).to_s.strip
          unless frontend.empty?
            host = URI.parse(frontend).host
            return host if host && !host.empty?
          end

          'localhost'
        end

        def smtp_settings
          discrete = discrete_smtp_settings
          return discrete if discrete

          mailertogo_url = SecureBidding::Environment.env_value('MAILERTOGO_URL', 'mailertogo_url').to_s.strip
          if mailertogo_url != ''
            uri = URI.parse(mailertogo_url)
            params = uri.query ? URI.decode_www_form(uri.query).to_h : {}

            {
              host: uri.host || smtp_host,
              port: (uri.port || smtp_port).to_i,
              username: URI.decode_www_form_component(uri.user.to_s),
              password: URI.decode_www_form_component(uri.password.to_s),
              auth: (params['authentication'] || params['auth'] || smtp_auth).to_sym,
              tls: smtp_use_tls?((uri.port || smtp_port).to_i)
            }
          else
            discrete_smtp_settings || {
              host: smtp_host,
              port: smtp_port.to_i,
              username: smtp_user,
              password: smtp_password,
              auth: smtp_auth.to_sym,
              tls: smtp_use_tls?(smtp_port.to_i)
            }
          end
        end

        def discrete_smtp_settings
          host = smtp_host.to_s.strip
          user = smtp_user.to_s.strip
          pass = smtp_password.to_s.strip
          return nil if host.empty? || user.empty? || pass.empty?

          port = smtp_port.to_i
          {
            host: host,
            port: port,
            username: user,
            password: pass,
            auth: smtp_auth.to_sym,
            tls: smtp_use_tls?(port)
          }
        end

        def smtp_use_tls?(port)
          explicit = SecureBidding::Environment.env_value(
            'MAILERTOGO_SMTP_TLS',
            'mailertogo_smtp_tls',
            'SMTP_TLS',
            'smtp_tls'
          ).to_s.strip.downcase
          return true if explicit == 'true'
          return false if explicit == 'false'

          port == 465
        end

        def smtp_host
          SecureBidding::Environment.env_value(
            'MAILERTOGO_SMTP_HOST',
            'mailertogo_smtp_host',
            default: 'localhost'
          )
        end

        def smtp_port
          SecureBidding::Environment.env_value(
            'MAILERTOGO_SMTP_PORT',
            'mailertogo_smtp_port',
            default: '587'
          )
        end

        def smtp_user
          SecureBidding::Environment.env_value(
            'MAILERTOGO_SMTP_USER',
            'mailertogo_smtp_user',
            default: ''
          )
        end

        def smtp_password
          SecureBidding::Environment.env_value(
            'MAILERTOGO_SMTP_PASSWORD',
            'mailertogo_smtp_password',
            default: ''
          )
        end

        def smtp_auth
          SecureBidding::Environment.env_value(
            'MAILERTOGO_SMTP_AUTH',
            'mailertogo_smtp_auth',
            default: 'plain'
          )
        end
      end
    end
  end
end
