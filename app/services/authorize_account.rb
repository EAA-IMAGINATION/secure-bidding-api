# frozen_string_literal: true

module SecureBidding
  class AuthorizeAccount
    class ForbiddenError < StandardError; end

    def self.call(auth:, username:, auth_scope: AuthScope::READ_ONLY)
      requester = requester_for(auth)
      requester_scope = auth.respond_to?(:scope) ? auth.scope : AuthScope.new
      account = Account.first(username: username)
      raise ForbiddenError unless account

      policy = Policies::AccountPolicy.new(requester, account, auth_scope: requester_scope)
      raise ForbiddenError unless policy.show?

      AuthorizedAccount.new(
        Routes::Auth.build_auth_payload(account, policy: policy),
        auth_scope,
        token_payload: session_payload(account)
      )
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
