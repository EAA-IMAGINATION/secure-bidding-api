# frozen_string_literal: true

module SecureBidding
  module Services
    module Accounts
      # Finds account resources by searchable encrypted fields.
      class SearchAccounts
        # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        def self.call(email: nil, phone: nil)
          if missing_criteria?(email, phone)
            return {
              ok: false,
              status: 400,
              error: 'email or phone query parameter is required'
            }
          end

          dataset = SecureBidding::Account.dataset
          if !email.to_s.strip.empty? && !phone.to_s.strip.empty?
            email_hash = SecureBidding::Account.search_hash(email)
            phone_hash = SecureBidding::Account.search_hash(phone)
            accounts = dataset.where(email_hash: email_hash).or(phone_hash: phone_hash).all
            return { ok: true, accounts: accounts }
          end

          unless email.to_s.strip.empty?
            email_hash = SecureBidding::Account.search_hash(email)
            return { ok: true, accounts: dataset.where(email_hash: email_hash).all }
          end

          phone_hash = SecureBidding::Account.search_hash(phone)
          { ok: true, accounts: dataset.where(phone_hash: phone_hash).all }
        end
        # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

        def self.missing_criteria?(email, phone)
          email.to_s.strip.empty? && phone.to_s.strip.empty?
        end
      end
    end
  end
end
