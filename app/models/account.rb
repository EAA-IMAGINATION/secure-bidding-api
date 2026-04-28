# frozen_string_literal: true

require_relative '../lib/search_hash'
require_relative '../lib/secure_db'
require_relative 'password'

module SecureBidding
  # Represents an authenticated user account.
  class Account < Sequel::Model(:accounts)
    VALID_ROLES = %w[admin member system_admin project_owner bidder].freeze

    plugin :uuid, field: :id
    plugin :whitelist_security
    plugin :association_dependencies
    set_allowed_columns :username, :system_role

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

    def has_system_role?(role_name)
      system_roles_dataset.where(name: role_name).count.positive?
    end
  end
end
