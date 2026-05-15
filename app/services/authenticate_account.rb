# frozen_string_literal: true

module SecureBidding
  # Service to authenticate account credentials
  class AuthenticateAccount
    # Error raised when credentials are invalid
    class UnauthorizedError < StandardError
      def initialize(credentials)
        @credentials = credentials
        super
      end

      def message
        "Invalid credentials for: #{@credentials[:username]}"
      end
    end

    def self.call(credentials)
      account = Account.first(username: credentials[:username])
      raise UnauthorizedError, credentials unless
        account&.check_password(credentials[:password])

      account
    end
  end
end
