# frozen_string_literal: true

module SecureBidding
  module Services
    module Auth
      # Shared email-link verification for registration, change-email, and resend.
      class Verification
        class Error < StandardError
          attr_reader :status, :body

          def initialize(status, body)
            @status = status
            @body = body.is_a?(Hash) ? body : { error: body }
            super(@body[:error] || @body['error'])
          end
        end

        def self.preview(token_string)
          token_string = token_string.to_s.strip
          raise Error.new(400, error: 'registration_token is required') if token_string.empty?

          account = account_for_token(token_string)
          if account
            validate_account_token!(account, token_string)
            load_payload(token_string)

            return {
              purpose: 'email_verification',
              username: account.username,
              email: account.email
            }
          end

          payload = load_payload(token_string)
          username = payload[:username].to_s.strip
          email = payload[:email].to_s.strip
          raise Error.new(404, error: 'Invalid token') if username.empty? || email.empty?

          {
            purpose: 'registration',
            username: username,
            email: email
          }
        end

        def self.complete(token_string, password: nil)
          preview_data = preview(token_string)

          case preview_data[:purpose]
          when 'email_verification'
            complete_email_verification(token_string)
          when 'registration'
            complete_registration(token_string, password, preview_data)
          else
            raise Error.new(500, error: 'Verification failed')
          end
        end

        def self.account_for_token(token_string)
          SecureBidding::Account.first(registration_token: token_string)
        end

        def self.validate_account_token!(account, token_string)
          unless account.registration_token == token_string
            raise Error.new(404, error: 'Invalid token')
          end

          return unless account.registration_token_expires_at && Time.now > account.registration_token_expires_at

          raise Error.new(403, error: 'Token has expired')
        end

        def self.load_payload(token_string)
          SecureBidding::AuthToken.load(token_string).payload
        rescue SecureBidding::ExpiredTokenError
          raise Error.new(403, error: 'Token has expired')
        rescue SecureBidding::InvalidTokenError
          raise Error.new(404, error: 'Invalid token')
        end

        def self.complete_email_verification(token_string)
          account = account_for_token(token_string)
          raise Error.new(404, error: 'Account not found') if account.nil?

          validate_account_token!(account, token_string)
          load_payload(token_string)

          account.verify_email!
          account.registration_token = nil
          account.registration_token_expires_at = nil
          account.save

          build_auth_payload(account).merge(status: 'verified')
        end

        def self.complete_registration(token_string, password, preview_data)
          password = password.to_s.strip
          if password.empty?
            raise Error.new(400, error: { password: ['is missing'] })
          end

          username = preview_data[:username]
          email = preview_data[:email]

          unless SecureBidding::Account.username_available?(username)
            raise Error.new(422, error: 'username already taken')
          end

          unless SecureBidding::Account.email_available?(email)
            raise Error.new(422, error: 'email already taken')
          end

          load_payload(token_string)

          account = SecureBidding::Account.new(username: username, system_role: 'member')
          account.set_email(email)
          account.set_password(password)
          account.verify_email!

          session_payload = {
            account_id: account.id,
            username: account.username,
            system_role: account.system_role
          }
          session_token = SecureBidding::AuthToken.new(
            session_payload,
            SecureBidding::AuthToken::ONE_WEEK,
            scope: SecureBidding::AuthScope.new
          ).to_s

          {
            token: session_token,
            account: build_auth_payload(account)
          }
        end

        def self.build_auth_payload(account)
          {
            id: account.id,
            username: account.username,
            email: account.email,
            system_role: account.system_role,
            system_roles: account.system_roles.map(&:name),
            email_verified: !account.email_verified_at.nil?,
            capabilities: account.capabilities
          }
        end

        private_class_method :account_for_token, :validate_account_token!, :load_payload,
                             :complete_email_verification, :complete_registration, :build_auth_payload
      end
    end
  end
end
