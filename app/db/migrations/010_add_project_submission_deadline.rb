# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:projects) do
      add_column :submission_deadline_at, DateTime, null: true
      add_index :submission_deadline_at
    end
  end

  down do
    alter_table(:projects) do
      drop_index :submission_deadline_at
      drop_column :submission_deadline_at
    end
  end
end
