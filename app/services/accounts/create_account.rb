# frozen_string_literal: true

module SecureBidding
  module Services
    module Accounts
      # Creates account resources with secured credentials and PII fields.
      class CreateAccount
        # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        ALLOWED_KEYS = %w[username password email phone system_role verification_token].freeze

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

          account = SecureBidding::Account.new(username: username, system_role: system_role)
          account.set_password(password)
          account.set_email(email)
          account.set_phone(phone) unless phone.to_s.strip.empty?
          account.save

          { ok: true, account: account }
        rescue Sequel::UniqueConstraintViolation
          error(400, 'username, email, or phone already exists')
        end
        # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

        private

        attr_reader :payload

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

        def phone
          payload['phone'] || payload[:phone]
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
