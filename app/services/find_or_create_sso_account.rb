# frozen_string_literal: true

require 'securerandom'

module SecureBidding
  class FindOrCreateSsoAccount
    class EmailConflictError < StandardError; end

    def self.call(provider:, external_id:, email:, email_verified:, avatar: nil, **)
      SecureBidding::Database.db.transaction do
        account =
          identity_account(provider, external_id) ||
          linkable_account(email, email_verified) ||
          create_member_account(provider:, email:, avatar:)

        link_identity(account, provider, external_id)
        account
      end
    end

    def self.identity_account(provider, external_id)
      SsoIdentity.first(provider:, external_id:)&.account
    end

    def self.linkable_account(email, email_verified)
      return nil unless email_verified && email

      Account.first(email_hash: Account.search_hash(email))
    end

    def self.create_member_account(provider:, email:, avatar:)
      if email && Account.first(email_hash: Account.search_hash(email))
        raise EmailConflictError, email
      end

      account = Account.new(
        username: unique_username(email, provider),
        system_role: 'member',
        avatar: avatar
      )
      account.set_email(email) if email
      account.set_password(SecureRandom.hex(16))
      account.save
      account
    end

    def self.link_identity(account, provider, external_id)
      return if SsoIdentity.first(provider:, external_id:)

      SsoIdentity.create(account_id: account.id, provider:, external_id:)
    end

    def self.unique_username(email, provider)
      base = email.to_s.split('@').first
      base = provider if base.to_s.empty?
      return base unless Account.first(username: base)

      suffixed = "#{base}@#{provider}"
      return suffixed unless Account.first(username: suffixed)

      "#{suffixed}-#{SecureRandom.hex(3)}"
    end
  end
end
