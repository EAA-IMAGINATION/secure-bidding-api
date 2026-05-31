# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:sso_identities) do
      primary_key :id
      foreign_key :account_id, :accounts, type: :uuid, null: false, on_delete: :cascade
      String :provider, null: false
      String :external_id, null: false, size: 255
      DateTime :created_at, null: false
      DateTime :updated_at, null: false
      index %i[provider external_id], unique: true
    end

    alter_table(:accounts) do
      add_column :avatar, String, text: true
    end
  end
end
