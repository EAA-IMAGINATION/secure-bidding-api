# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:projects) do
      add_column :state, String, null: false, default: 'saved'
      add_index :state
    end
  end

  down do
    alter_table(:projects) do
      drop_index :state
      drop_column :state
    end
  end
end
