# frozen_string_literal: true

module SecureBidding
  class AuthorizeAccount
    class ForbiddenError < StandardError; end
    class InvalidScopeError < StandardError; end
    class ScopeNotPermittedError < StandardError; end

    def self.call(auth:, username:, auth_scope: nil)
      requester = requester_for(auth)
      requester_scope = auth.respond_to?(:scope) ? auth.scope : AuthScope.new
      account = Account.first(username: username)
      raise ForbiddenError unless account

      policy = Policies::AccountPolicy.new(requester, account, auth_scope: requester_scope)
      raise ForbiddenError unless policy.show?

      resolved_scope = resolve_api_key_scope(auth_scope, requester_scope)

      AuthorizedAccount.new(
        Routes::Auth.build_auth_payload(account, policy: policy),
        resolved_scope,
        token_payload: session_payload(account)
      )
    end

    def self.resolve_api_key_scope(requested, grantor_scope)
      scope_str = requested.to_s.strip
      scope_str = AuthScope::READ_ONLY if scope_str.empty?

      unless AuthScope.api_key_scope_allowed?(scope_str)
        raise InvalidScopeError, 'Scope is not allowed for API keys'
      end

      requested_scope = AuthScope.new(scope_str)
      unless requested_scope.permitted_by?(grantor_scope)
        raise ScopeNotPermittedError, 'Requested scope exceeds your session permissions'
      end

      scope_str
    end

    def self.requester_for(auth)
      return nil unless auth

      payload = auth.respond_to?(:account) ? auth.account : auth
      account_id = payload[:account_id] || payload['account_id']
      Account[account_id] if account_id
    end

    def self.session_payload(account)
      {
        account_id: account.id,
        username: account.username,
        system_role: account.system_role
      }
    end
  end
end
