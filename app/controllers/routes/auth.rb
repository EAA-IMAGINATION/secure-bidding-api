# frozen_string_literal: true

module SecureBidding
  module Routes
    # Handles authentication endpoints under /auth.
    # Parses credentials, invokes the AuthenticateAccount service, and returns
    # the authenticated account payload or an appropriate error response.
    module Auth
      def self.parse_signed_body(req)
        HttpRequest.new(req).signed_body_data
      rescue SignedRequest::VerificationError
        req.halt 403, { error: 'Must sign request' }.to_json
      end

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
          req.on 'verification-preview' do
            req.post { handle_verification_preview(req, app) }
          end
          req.on 'registration-preview' do
            req.post { handle_verification_preview(req, app) }
          end
          req.on 'verify' do
            req.post { handle_verify(req, app) }
          end
          req.on 'verify-email' do
            req.post { handle_verify(req, app) }
          end
          req.on 'sso' do
            req.post { handle_sso(req, app) }
          end
        end
      end

      def self.handle_authenticate(req, app)
        credentials = parse_signed_body(req)
        form = SecureBidding::Forms::AuthenticateForm.new
        result = form.call(credentials)
        unless result.success?
          req.halt 400, { error: result.errors.to_h }.to_json
        end

        auth_account = AuthenticateAccount.call(credentials)

        session_payload = {
          account_id: auth_account.id,
          username: auth_account.username,
          system_role: auth_account.system_role
        }
        session_token = SecureBidding::AuthToken.new(
          session_payload,
          SecureBidding::AuthToken::ONE_WEEK,
          scope: SecureBidding::AuthScope.new
        ).to_s

        build_auth_payload(auth_account).merge(token: session_token)
      rescue AuthenticateAccount::UnauthorizedError => e
        log_and_halt_invalid_credentials(app, req, e)
      rescue StandardError => e
        log_and_halt_auth_error(app, req, e)
      end

      def self.handle_availability(req, app)
        data = parse_signed_body(req)
        result = SecureBidding::Forms::AvailabilityForm.new.call(data)
        unless result.success?
          req.halt 400, { error: result.errors.to_h }.to_json
        end

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
        data = parse_signed_body(req)
        result = SecureBidding::Forms::RegisterForm.new.call(data)
        unless result.success?
          return req.halt(400, { error: result.errors.to_h }.to_json)
        end

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
          SecureBidding::AuthToken::VERIFICATION_LINK_TTL
        )

        verification_link = build_verification_link(req, registration_token)

        begin
          SecureBidding::Services::Email::SendVerification.call(
            account: account,
            verification_link: verification_link,
            purpose: :registration
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
        data = parse_signed_body(req)
        registration_token = data[:registration_token].to_s.strip
        if registration_token.empty?
          return req.halt(400, { error: 'registration_token is required' }.to_json)
        end

        SecureBidding::Services::Auth::Verification.complete(
          registration_token,
          password: data[:password]
        )
      rescue SecureBidding::Services::Auth::Verification::Error => e
        req.halt e.status, e.body.to_json
      rescue Sequel::UniqueConstraintViolation
        req.halt 422, { error: 'Account data already exists' }.to_json
      rescue StandardError => e
        app.class::APP_LOGGER.error("Verification error: #{e.message}")
        req.halt 500, { error: 'Verification failed' }.to_json
      end

      def self.build_auth_payload(auth_account, policy: nil)
        policy ||= SecureBidding::Policies::AccountPolicy.new(auth_account, auth_account)
        {
          id: auth_account.id,
          username: auth_account.username,
          email: auth_account.email,
          system_role: auth_account.system_role,
          system_roles: auth_account.system_roles.map(&:name),
          email_verified: !auth_account.email_verified_at.nil?,
          capabilities: auth_account.capabilities,
          policy: policy.summary
        }
      end

      def self.handle_sso(req, app)
        data = parse_signed_body(req)
        id_token = data[:id_token].to_s.strip
        req.halt(400, { error: 'id_token is required' }.to_json) if id_token.empty?

        SecureBidding::AuthenticateSso.call(id_token)
      rescue SecureBidding::OidcVerifier::VerificationError => e
        app.class::APP_LOGGER.warn("SSO verification failed: #{e.message}")
        req.halt 401, { error: 'Invalid SSO credentials' }.to_json
      rescue SecureBidding::FindOrCreateSsoAccount::EmailConflictError
        req.halt 409, { error: 'Email already registered to another account' }.to_json
      rescue StandardError => e
        app.class::APP_LOGGER.error("SSO error: #{e.message}")
        req.halt 500, { error: 'SSO authentication failed' }.to_json
      end

      def self.frontend_base_url(req)
        frontend = SecureBidding::Environment.env_value('FRONTEND_APP_URL', 'frontend_app_url').to_s.strip
        return frontend.chomp('/') unless frontend.empty?

        app_url = SecureBidding::Environment.env_value('APP_URL', 'app_url').to_s.strip
        return app_url.chomp('/') unless app_url.empty?

        "#{req.scheme}://#{req.host}"
      end

      def self.build_verification_link(req, registration_token)
        "#{frontend_base_url(req)}/verify-email?token=#{registration_token}"
      end

      def self.build_email_verification_link(req, registration_token)
        build_verification_link(req, registration_token)
      end

      def self.handle_verification_preview(req, app)
        data = parse_signed_body(req)
        registration_token = data[:registration_token].to_s.strip
        SecureBidding::Services::Auth::Verification.preview(registration_token)
      rescue SecureBidding::Services::Auth::Verification::Error => e
        req.halt e.status, e.body.to_json
      rescue StandardError => e
        app.class::APP_LOGGER.error("Verification preview error: #{e.message}")
        req.halt 500, { error: 'Unable to load verification preview' }.to_json
      end

      def self.log_and_halt_invalid_credentials(app, req, err)
        app.class::APP_LOGGER.warn("Authentication failed: #{err.message}")
        req.halt 401, { error: 'Invalid credentials' }.to_json
      end

      def self.log_and_halt_auth_error(app, req, err)
        app.class::APP_LOGGER.error("Authentication error: #{err.message}")
        req.halt 500, { error: 'Authentication service error' }.to_json
      end
    end
  end
end
