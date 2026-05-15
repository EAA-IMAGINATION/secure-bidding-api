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
        end
      end

      def self.handle_authenticate(req, app)
        credentials = HttpRequest.new(req).body_data
        auth_account = AuthenticateAccount.call(credentials)

        build_auth_payload(auth_account)
      rescue AuthenticateAccount::UnauthorizedError => e
        log_and_halt_invalid_credentials(app, req, e)
      rescue StandardError => e
        log_and_halt_auth_error(app, req, e)
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
