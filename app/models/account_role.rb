# frozen_string_literal: true

module SecureBidding
  # Join model linking accounts to system roles.
  class AccountRole < Sequel::Model(:account_roles)
    plugin :whitelist_security
    set_allowed_columns :account_id, :role_id

    many_to_one :account, key: :account_id, class: 'SecureBidding::Account'
    many_to_one :role, key: :role_id, class: 'SecureBidding::Role'
  end
end
