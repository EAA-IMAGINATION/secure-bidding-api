# frozen_string_literal: true

module SecureBidding
  class AuthenticateSso
    def self.call(id_token)
      claims = GoogleIdToken.verify(id_token)
      account = FindOrCreateSsoAccount.call(**GoogleAccount.new(claims).to_h)
      build_response(account)
    end

    def self.build_response(account)
      payload = session_payload(account)
      token = AuthToken.new(payload, AuthToken::ONE_WEEK, scope: AuthScope.new).to_s
      Routes::Auth.build_auth_payload(account).merge(token: token)
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
