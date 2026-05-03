# frozen_string_literal: true

module SecureBidding
  module Services
    module Accounts
      # Updates account resources through explicit mutable fields.
      class UpdateAccount
        ALLOWED_KEYS = %w[password email phone system_role].freeze

        # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
        def self.call(account, payload)
          new(account, payload).call
        end

        def initialize(account, payload)
          @account = account
          @payload = payload || {}
        end

        def call
          return error(400, 'Invalid account attributes') unless valid_keys?
          return error(400, 'At least one updatable field is required') unless mutation?
          return error(400, 'system_role must be admin or member') if invalid_role?

          account.system_role = system_role unless system_role.nil?
          account.set_password(password) unless password.nil?
          account.set_email(email) unless email.nil?
          account.set_phone(phone) unless phone.nil?
          account.save
          { ok: true, account: account }
        rescue Sequel::UniqueConstraintViolation
          error(400, 'username, email, or phone already exists')
        end
        # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

        private

        attr_reader :account, :payload

        def valid_keys?
          (payload.keys.map(&:to_s) - ALLOWED_KEYS).empty?
        end

        def mutation?
          [password, email, phone, system_role].any? { |value| !value.nil? }
        end

        def invalid_role?
          !system_role.nil? && !SecureBidding::Account::VALID_ROLES.include?(system_role.to_s)
        end

        def password
          value = payload['password'] || payload[:password]
          value if !value.nil? && !value.to_s.strip.empty?
        end

        def email
          value = payload['email'] || payload[:email]
          value if !value.nil? && !value.to_s.strip.empty?
        end

        def phone
          value = payload['phone'] || payload[:phone]
          value if !value.nil? && !value.to_s.strip.empty?
        end

        def system_role
          payload['system_role'] || payload[:system_role]
        end

        def error(status, message)
          { ok: false, status: status, error: message }
        end
      end
    end
  end
end
