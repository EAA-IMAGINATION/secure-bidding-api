# frozen_string_literal: true

module SecureBidding
  module Services
    module Accounts
      # Replaces the account set with a fresh bootstrap admin account.
      class ResetAccounts
        ALLOWED_KEYS = %w[username password email phone system_role].freeze

        def self.call(payload)
          new(payload).call
        end

        def initialize(payload)
          @payload = payload || {}
        end

        def call
          return error(400, 'Invalid account attributes') unless valid_keys?
          return error(400, 'username, password, and email are required') if required_missing?
          return error(400, 'system_role must be admin or member') unless valid_role?

          result = nil
          SecureBidding::Database.db.transaction do
            clear_accounts!
            result = SecureBidding::Services::Accounts::CreateAccount.call(payload)
            raise Sequel::Rollback unless result[:ok]
          end

          # Mark seeded admin as verified so seed accounts are usable without email flow
          if result && result[:ok] && result[:account] && result[:account].email_verified_at.nil?
            result[:account].verify_email!
          end

          result
        end

        private

        attr_reader :payload

        def clear_accounts!
          SecureBidding::AccountProject.dataset.delete
          SecureBidding::AccountRole.dataset.delete
          SecureBidding::ProjectMembership.dataset.delete
          SecureBidding::Account.dataset.delete
        end

        def valid_keys?
          (payload.keys.map(&:to_s) - ALLOWED_KEYS).empty?
        end

        def required_missing?
          [username, password, email].any? { |value| value.to_s.strip.empty? }
        end

        def valid_role?
          SecureBidding::Account::VALID_ROLES.include?(system_role)
        end

        def username
          payload['username'] || payload[:username]
        end

        def password
          payload['password'] || payload[:password]
        end

        def email
          payload['email'] || payload[:email]
        end

        def system_role
          (payload['system_role'] || payload[:system_role] || 'member').to_s
        end

        def error(status, message)
          { ok: false, status: status, error: message }
        end
      end
    end
  end
end
