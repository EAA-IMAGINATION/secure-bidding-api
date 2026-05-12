# frozen_string_literal: true

Sequel.migration do
  up do
    drop_table?(:secrets)
    drop_table?(:accounts)

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

  down do
    drop_table?(:secrets)
    drop_table?(:accounts)

    create_table(:accounts) do
      primary_key :id
      String :username, null: false, unique: true
      String :email, null: false, unique: true
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table(:secrets) do
      primary_key :id
      foreign_key :account_id, :accounts, null: false, on_delete: :cascade
      String :title, null: false
      File :encrypted_data, null: false
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      index :account_id
      unique %i[account_id title]
    end
  end
end
