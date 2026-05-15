# frozen_string_literal: true

Sequel.migration do
  change do
    create_table?(:secrets) do
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
