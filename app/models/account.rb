# frozen_string_literal: true

require_relative '../lib/search_hash'
require_relative '../lib/secure_db'
require_relative 'password'

module SecureBidding
  # Represents an authenticated user account.
  class Account < Sequel::Model(:accounts)
    VALID_ROLES = %w[admin member system_admin project_owner bidder].freeze
    PROFILE_ROLE_ORDER = %w[admin system_admin member project_owner bidder freelancer].freeze

    plugin :uuid, field: :id
    plugin :whitelist_security
    plugin :association_dependencies
    set_allowed_columns :username, :system_role, :avatar

    one_to_many :sso_identities, key: :account_id, class: 'SecureBidding::SsoIdentity'

    one_to_many :account_projects, key: :account_id, class: 'SecureBidding::AccountProject'
    one_to_many :account_roles, key: :account_id, class: 'SecureBidding::AccountRole'
    one_to_many :project_memberships, key: :account_id, class: 'SecureBidding::ProjectMembership'
    many_to_many :collaborations,
                 class: 'SecureBidding::Project',
                 join_table: :account_projects,
                 left_key: :account_id,
                 right_key: :project_id
    many_to_many :system_roles,
                 class: 'SecureBidding::Role',
                 join_table: :account_roles,
                 left_key: :account_id,
                 right_key: :role_id

    add_association_dependencies account_projects: :delete, account_roles: :delete, project_memberships: :delete

    def add_collaboration(project, collaboration_role: 'collaborator')
      AccountProject.first(account_id: id, project_id: project.id) ||
        AccountProject.create(
          account_id: id,
          project_id: project.id,
          collaboration_role: collaboration_role
        )
    end

    # rubocop:disable Naming/AccessorMethodName
    def set_password(plaintext_password)
      digest = Password.digest(plaintext_password)
      self.password_salt = digest[:salt]
      self.password_hash = digest[:hash]
    end

    def check_password(candidate_password)
      Password.valid?(candidate_password, salt: password_salt, hash: password_hash)
    end

    def set_email(value)
      self.email_secure = SecureDB.encrypt(value)
      self.email_hash = self.class.search_hash(value)
    end

    def set_phone(value)
      self.phone_secure = SecureDB.encrypt(value)
      self.phone_hash = self.class.search_hash(value)
    end
    # rubocop:enable Naming/AccessorMethodName

    def email
      email_secure.nil? ? nil : SecureDB.decrypt(email_secure)
    end

    def phone
      phone_secure.nil? ? nil : SecureDB.decrypt(phone_secure)
    end

    def self.search_hash(value)
      SearchHash.digest(value)
    end

    def self.email_available?(email)
      email_hash = search_hash(email)
      where(email_hash: email_hash).count.zero?
    end

    def self.username_available?(username)
      where(username: username).count.zero?
    end

    def system_role?(role_name)
      system_role == role_name || system_roles_dataset.where(name: role_name).count.positive?
    end

    def capabilities
      privileged = system_role?('admin') || system_role?('system_admin')
      verified = !email_verified_at.nil?
      {
        admin: system_role?('admin'),
        system_admin: system_role?('system_admin'),
        project_owner: system_role?('project_owner'),
        bidder: system_role?('bidder'),
        can_manage_accounts: privileged,
        can_assign_system_roles: privileged,
        can_create_projects: !privileged && verified
      }
    end

    def profile_roles
      roles = []
      roles << system_role if system_role.to_s.strip != ''
      roles.concat(system_roles_dataset.order(:name).select_map(:name))
      roles << 'project_owner' if project_owner_membership? || collaboration_owner?
      roles << 'bidder' if bid_submissions_dataset.count.positive?
      roles << 'freelancer' if awarded_bid_submissions_dataset.count.positive?

      roles.uniq.sort_by { |role| [PROFILE_ROLE_ORDER.index(role) || PROFILE_ROLE_ORDER.length, role] }
    end

    def self.by_registration_token(token_string)
      account_payload = SecureBidding::AuthToken.load(token_string).payload
      self[account_payload[:account_id]]
    rescue SecureBidding::InvalidTokenError, SecureBidding::ExpiredTokenError => e
      raise e
    end

    def set_registration_token(expiration = SecureBidding::AuthToken::VERIFICATION_LINK_TTL)
      token = SecureBidding::AuthToken.new(
        { account_id: id },
        expiration
      )
      self.registration_token = token.to_s
      self.registration_token_expires_at = Time.now + expiration
    end

    def verify_email!
      self.email_verified_at = Time.now
      save
    end

    private

    def project_owner_membership?
      owner_role = Role.first(name: 'project_owner')
      return false unless owner_role

      project_memberships_dataset.where(role_id: owner_role.id).count.positive?
    end

    def collaboration_owner?
      account_projects_dataset.where(collaboration_role: 'owner').count.positive?
    end

    def bid_submissions_dataset
      SecureBidding::BidSubmission.where(bidder_account_id: id)
    end

    def awarded_bid_submissions_dataset
      awarded_ids = SecureBidding::Project
                      .where(Sequel.~(awarded_bid_submission_id: nil))
                      .select_map(:awarded_bid_submission_id)
      return SecureBidding::BidSubmission.where(false) if awarded_ids.empty?

      SecureBidding::BidSubmission.where(id: awarded_ids, bidder_account_id: id)
    end
  end
end
