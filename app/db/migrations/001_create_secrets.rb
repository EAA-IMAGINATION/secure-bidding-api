# frozen_string_literal: true

Sequel.migration do
  change do
    create_table?(:secrets) do
      primary_key :id
      Integer :account_id, null: false
      String :title, null: false
      File :encrypted_data, null: false
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end
  end
end
