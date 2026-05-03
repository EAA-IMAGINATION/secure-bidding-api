# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength

Sequel.migration do
  up do
    drop_table?(:secrets)
    drop_table?(:accounts)

    create_table(:projects) do
      column :id, :uuid, primary_key: true
      String :title, null: false, unique: true
      Integer :budget_cents, null: false
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table(:bid_submissions) do
      column :id, :uuid, primary_key: true
      foreign_key :project_id, :projects, type: :uuid, null: false, on_delete: :cascade
      String :contractor_alias, null: false
      File :secure_encrypted_bid, null: false
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      index :project_id
      unique %i[project_id contractor_alias]
    end
  end

  down do
    drop_table?(:bid_submissions)
    drop_table?(:projects)

    create_table(:accounts) do
      column :id, :uuid, primary_key: true
      String :username, null: false, unique: true
      String :email, null: false, unique: true
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table(:secrets) do
      column :id, :uuid, primary_key: true
      foreign_key :account_id, :accounts, type: :uuid, null: false, on_delete: :cascade
      String :title, null: false
      File :secure_encrypted_data, null: false
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      index :account_id
      unique %i[account_id title]
    end
  end
end
# rubocop:enable Metrics/BlockLength
