# frozen_string_literal: true

module SecureBidding
  class Account < Sequel::Model(:accounts)
    plugin :uuid, field: :id
    plugin :whitelist_security
    set_allowed_columns :username, :email

    one_to_many :secrets, key: :account_id, class: 'SecureBidding::Secret'
  end
end
