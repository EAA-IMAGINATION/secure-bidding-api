# frozen_string_literal: true

require_relative '../lib/auth_scope'
require_relative '../lib/auth_token'

module SecureBidding
  class AuthorizedAccount
    attr_reader :account, :scope

    def initialize(account_payload, auth_scope = nil, token_payload: nil, expiration: AuthToken::ONE_MONTH)
      @account = account_payload
      @token_payload = token_payload || account_payload
      @expiration = expiration
      @scope =
        case auth_scope
        when AuthScope then auth_scope
        when nil then AuthScope.new
        else AuthScope.new(auth_scope)
        end
    end

    def token
      AuthToken.new(@token_payload, @expiration, scope: @scope).to_s
    end
  end
end
