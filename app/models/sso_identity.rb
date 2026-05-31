# frozen_string_literal: true

require 'sequel'

module SecureBidding
  class SsoIdentity < Sequel::Model(:sso_identities)
    many_to_one :account, class: 'SecureBidding::Account'

    plugin :whitelist_security
    set_allowed_columns :account_id, :provider, :external_id

    plugin :timestamps, update_on_create: true
  end
end
