Sequel.migration do
  up do
    alter_table(:projects) do
      add_column :nacl_public_key, String
      add_column :nacl_encrypted_private_key, String
    end
  end

  down do
    alter_table(:projects) do
      drop_column :nacl_encrypted_private_key
      drop_column :nacl_public_key
    end
  end
end
