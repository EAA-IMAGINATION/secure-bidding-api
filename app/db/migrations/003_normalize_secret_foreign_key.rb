# frozen_string_literal: true

Sequel.migration do
  up do
    secret_columns = self[:secrets].columns
    account_columns = self[:accounts].columns

    secret_has_owner_id = secret_columns.include?(:owner_id)
    secret_has_account_id = secret_columns.include?(:account_id)
    secret_has_created_at = secret_columns.include?(:created_at)
    secret_has_updated_at = secret_columns.include?(:updated_at)
    account_has_created_at = account_columns.include?(:created_at)
    account_has_updated_at = account_columns.include?(:updated_at)

    alter_table(:secrets) do
      rename_column :owner_id, :account_id if secret_has_owner_id && !secret_has_account_id
      add_column :created_at, DateTime, null: false, default: Sequel::CURRENT_TIMESTAMP unless secret_has_created_at
      add_column :updated_at, DateTime, null: false, default: Sequel::CURRENT_TIMESTAMP unless secret_has_updated_at
    end

    alter_table(:accounts) do
      add_column :created_at, DateTime, null: false, default: Sequel::CURRENT_TIMESTAMP unless account_has_created_at
      add_column :updated_at, DateTime, null: false, default: Sequel::CURRENT_TIMESTAMP unless account_has_updated_at
    end
  end

  down do
    secret_columns = self[:secrets].columns
    account_columns = self[:accounts].columns

    secret_has_owner_id = secret_columns.include?(:owner_id)
    secret_has_account_id = secret_columns.include?(:account_id)
    secret_has_created_at = secret_columns.include?(:created_at)
    secret_has_updated_at = secret_columns.include?(:updated_at)
    account_has_created_at = account_columns.include?(:created_at)
    account_has_updated_at = account_columns.include?(:updated_at)

    alter_table(:secrets) do
      drop_column :updated_at if secret_has_updated_at
      drop_column :created_at if secret_has_created_at
      rename_column :account_id, :owner_id if secret_has_account_id && !secret_has_owner_id
    end

    alter_table(:accounts) do
      drop_column :updated_at if account_has_updated_at
      drop_column :created_at if account_has_created_at
    end
  end
end
