# frozen_string_literal: true

module SecureBidding
  module Routes
    module Auth
      def self.call(r, app)
        r.on 'auth' do
          r.on 'authenticate' do
            r.post do
              credentials = HttpRequest.new(r).body_data
              auth_account = AuthenticateAccount.call(credentials)
              {
                id: auth_account.id,
                username: auth_account.username,
                email: auth_account.email,
                system_role: auth_account.system_role,
                system_roles: auth_account.system_roles.map(&:name)
              }
            rescue AuthenticateAccount::UnauthorizedError => e
              app.class::APP_LOGGER.warn("Authentication failed: #{e.message}")
              r.halt 403, { error: 'Invalid credentials' }.to_json
            rescue StandardError => e
              app.class::APP_LOGGER.error("Authentication error: #{e.message}")
              r.halt 500, { error: 'Authentication service error' }.to_json
            end
          end
        end
      end
    end
  end
end
