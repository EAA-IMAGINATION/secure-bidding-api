# frozen_string_literal: true

module SecureBidding
  class Account < Sequel::Model(:accounts)
    one_to_many :secrets, key: :account_id, class: 'SecureBidding::Secret'
  end
end
