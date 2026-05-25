# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
Sequel.migration do
  change do
    create_table?(:accounts) do
      column :id, :uuid, primary_key: true
      String :username, null: false, unique: true
      String :system_role, null: false, default: 'member'
      String :password_salt, null: false
      String :password_hash, null: false
      File :email_secure, null: false
      String :email_hash, null: false, unique: true
      File :phone_secure
      String :phone_hash
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      index :system_role
      index :phone_hash, unique: true
    end

    create_table?(:account_projects) do
      foreign_key :account_id, :accounts, type: :uuid, null: false, on_delete: :cascade
      foreign_key :project_id, :projects, type: :uuid, null: false, on_delete: :cascade
      String :collaboration_role, null: false, default: 'collaborator'
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      primary_key %i[account_id project_id]
      index :project_id
      index :collaboration_role
    end
  end
end
# rubocop:enable Metrics/BlockLength
