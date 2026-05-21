# frozen_string_literal: true

module SecureBidding
  module Routes
    # Handles authentication endpoints under /auth.
    # Parses credentials, invokes the AuthenticateAccount service, and returns
    # the authenticated account payload or an appropriate error response.
    module Auth
      def self.call(req, app)
        req.on 'auth' do
          req.on 'authenticate' do
            req.post { handle_authenticate(req, app) }
          end
          req.on 'availability' do
            req.post { handle_availability(req, app) }
          end
          req.on 'register' do
            req.post { handle_register(req, app) }
          end
          req.on 'verify' do
            req.post { handle_verify(req, app) }
          end
        end
      end

      def self.handle_authenticate(req, app)
        credentials = HttpRequest.new(req).body_data
        auth_account = AuthenticateAccount.call(credentials)

        session_payload = {
          account_id: auth_account.id,
          username: auth_account.username,
          system_role: auth_account.system_role
        }
        session_token = SecureBidding::AuthToken.tokenize(session_payload, SecureBidding::AuthToken::ONE_WEEK)

        build_auth_payload(auth_account).merge(token: session_token)
      rescue AuthenticateAccount::UnauthorizedError => e
        log_and_halt_invalid_credentials(app, req, e)
      rescue StandardError => e
        log_and_halt_auth_error(app, req, e)
      end

      def self.handle_availability(req, app)
        data = HttpRequest.new(req).body_data
        username = data[:username].to_s.strip
        email = data[:email].to_s.strip

        available_username = username.length.positive? ? SecureBidding::Account.username_available?(username) : nil
        available_email = email.length.positive? ? SecureBidding::Account.email_available?(email) : nil

        {
          available: {
            username: available_username,
            email: available_email
          }
        }
      rescue StandardError => e
        app.class::APP_LOGGER.error("Availability check error: #{e.message}")
        req.halt 400, { error: 'Invalid request' }.to_json
      end

      def self.handle_register(req, app)
        data = HttpRequest.new(req).body_data
        username = data[:username].to_s.strip
        email = data[:email].to_s.strip

        return req.halt(400, { error: 'username and email are required' }.to_json) if username.empty? || email.empty?

        unless SecureBidding::Account.username_available?(username)
          return req.halt(422, { error: 'username already taken' }.to_json)
        end

        unless SecureBidding::Account.email_available?(email)
          return req.halt(422, { error: 'email already taken' }.to_json)
        end

        account = SecureBidding::Account.new(username: username, system_role: 'member')
        account.set_email(email)
        registration_token = SecureBidding::AuthToken.tokenize(
          { username: username, email: email },
          SecureBidding::AuthToken::ONE_HOUR
        )

        verification_url = build_verification_url(app, req)

        begin
          SecureBidding::Services::Email::SendVerification.call(
            account: account,
            registration_token: registration_token,
            verification_url: verification_url
          )
        rescue SecureBidding::Services::Email::SendVerification::MailerToGoError => e
          app.class::APP_LOGGER.error("Email service error: #{e.message}")
          return req.halt(500, { error: 'Failed to send verification email' }.to_json)
        end

        {
          message: 'Check your email to verify your account'
        }
      rescue Sequel::UniqueConstraintViolation
        req.halt 422, { error: 'Account data already exists' }.to_json
      rescue StandardError => e
        app.class::APP_LOGGER.error("Registration error: #{e.message}")
        req.halt 400, { error: 'Invalid request' }.to_json
      end

      def self.handle_verify(req, app)
        data = HttpRequest.new(req).body_data
        registration_token = data[:registration_token].to_s.strip
        password = data[:password].to_s.strip

        return req.halt(400, { error: 'registration_token and password are required' }.to_json) if registration_token.empty? || password.empty?

        begin
          token_data = SecureBidding::AuthToken.load(registration_token)
          payload = token_data.payload
          username = payload[:username]
          email = payload[:email]
        rescue SecureBidding::ExpiredTokenError
          return req.halt(403, { error: 'Token has expired' }.to_json)
        rescue SecureBidding::InvalidTokenError
          return req.halt(404, { error: 'Invalid token' }.to_json)
        end

        unless SecureBidding::Account.username_available?(username)
          return req.halt(422, { error: 'username already taken' }.to_json)
        end

        unless SecureBidding::Account.email_available?(email)
          return req.halt(422, { error: 'email already taken' }.to_json)
        end

        account = SecureBidding::Account.new(username: username, system_role: 'member')
        account.set_email(email)
        account.set_password(password)
        account.verify_email!

        session_payload = {
          account_id: account.id,
          username: account.username,
          system_role: account.system_role
        }
        session_token = SecureBidding::AuthToken.tokenize(session_payload, SecureBidding::AuthToken::ONE_WEEK)

        {
          token: session_token,
          account: {
            id: account.id,
            username: account.username,
            email: account.email
          }
        }
      rescue Sequel::UniqueConstraintViolation
        req.halt 422, { error: 'Account data already exists' }.to_json
      rescue StandardError => e
        app.class::APP_LOGGER.error("Verification error: #{e.message}")
        req.halt 500, { error: 'Verification failed' }.to_json
      end

      def self.build_auth_payload(auth_account)
        {
          id: auth_account.id,
          username: auth_account.username,
          email: auth_account.email,
          system_role: auth_account.system_role,
          system_roles: auth_account.system_roles.map(&:name)
        }
      end

      def self.build_verification_url(app, req)
        scheme = req.scheme
        host = req.host
        "#{scheme}://#{host}/verify-email"
      end

      def self.log_and_halt_invalid_credentials(app, req, err)
        app.class::APP_LOGGER.warn("Authentication failed: #{err.message}")
        req.halt 403, { error: 'Invalid credentials' }.to_json
      end

      def self.log_and_halt_auth_error(app, req, err)
        app.class::APP_LOGGER.error("Authentication error: #{err.message}")
        req.halt 500, { error: 'Authentication service error' }.to_json
      end
    end
  end
end
