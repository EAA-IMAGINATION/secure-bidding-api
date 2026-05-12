# frozen_string_literal: true

module SecureBidding
  module Services
    module Accounts
      # Fetches a single account by ID.
      class GetAccount
        def self.call(id)
          SecureBidding::Account[id]
        end
      end
    end
  end
end
