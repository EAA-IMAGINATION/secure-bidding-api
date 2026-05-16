# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:accounts) do
      add_column :registration_token, String, null: true
      add_column :registration_token_expires_at, DateTime, null: true
      add_column :email_verified_at, DateTime, null: true, default: nil
    end

    alter_table(:accounts) do
      add_index :registration_token, name: :accounts_registration_token_idx
    end
  end

  down do
    alter_table(:accounts) do
      drop_index :registration_token, name: :accounts_registration_token_idx
    end

    alter_table(:accounts) do
      drop_column :registration_token
      drop_column :registration_token_expires_at
      drop_column :email_verified_at
    end
  end
end
