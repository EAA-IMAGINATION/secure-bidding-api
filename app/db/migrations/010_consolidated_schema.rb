# frozen_string_literal: true

# Consolidated, non-destructive migration that ensures the current production schema.
# This migration is intentionally idempotent and adds missing columns/tables without
# dropping existing data.
Sequel.migration do
  up do
    # Core account table
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

    # Projects and bid submissions
    create_table?(:projects) do
      column :id, :uuid, primary_key: true
      String :title, null: false, unique: true
      Integer :budget_cents, null: false
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table?(:bid_submissions) do
      column :id, :uuid, primary_key: true
      foreign_key :project_id, :projects, type: :uuid, null: false, on_delete: :cascade
      String :contractor_alias, null: false
      File :secure_encrypted_bid, null: false
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      index :project_id
      unique %i[project_id contractor_alias]
    end

    # Account <-> Project join
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

    # Roles and memberships
    create_table?(:roles) do
      primary_key :id
      String :name, null: false, unique: true
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table?(:account_roles) do
      foreign_key :account_id, :accounts, type: :uuid, null: false, on_delete: :cascade
      foreign_key :role_id, :roles, null: false, on_delete: :cascade
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      primary_key %i[account_id role_id]
    end

    create_table?(:project_memberships) do
      column :id, :uuid, primary_key: true
      foreign_key :account_id, :accounts, type: :uuid, null: false, on_delete: :cascade
      foreign_key :project_id, :projects, type: :uuid, null: false, on_delete: :cascade
      foreign_key :role_id, :roles, null: false, on_delete: :restrict
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      unique %i[account_id project_id role_id]
      index :project_id
    end

    create_table?(:payments) do
      column :id, :uuid, primary_key: true
      foreign_key :bid_submission_id, :bid_submissions, type: :uuid, null: false, on_delete: :cascade
      TrueClass :paid, null: false, default: false
      String :method
      String :reference
      DateTime :paid_at
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      unique :bid_submission_id
      index :paid
    end

    # Add registration/verification columns if missing
    accounts_cols = self[:accounts].columns rescue []
    unless accounts_cols.include?(:registration_token)
      alter_table(:accounts) do
        add_column :registration_token, String, null: true
        add_column :registration_token_expires_at, DateTime, null: true
        add_column :email_verified_at, DateTime, null: true, default: nil
      end
    end

    # Add project state if missing
    projects_cols = self[:projects].columns rescue []
    unless projects_cols.include?(:state)
      alter_table(:projects) do
        add_column :state, String, null: false, default: 'saved'
      end
    end

    # Ensure indexes exist (tolerate duplicates where the adapter raises)
    begin
      alter_table(:accounts) do
        add_index :system_role
        add_index :phone_hash, unique: true
      end
    rescue StandardError
      # ignore duplicate-index errors on some adapters
    end

    begin
      alter_table(:projects) do
        add_index :state
      end
    rescue StandardError
      # ignore duplicate-index errors on some adapters
    end
  end

  down do
    # Intentionally left blank to avoid destructive rollbacks in production.
  end
end
