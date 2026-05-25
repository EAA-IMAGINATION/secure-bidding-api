# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
Sequel.migration do
  change do
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
  end
end
# rubocop:enable Metrics/BlockLength
