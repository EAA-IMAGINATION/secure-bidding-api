# frozen_string_literal: true

Sequel.migration do
  up do
    project_columns = schema(:projects).map(&:first).map(&:to_s)
    alter_table(:projects) do
      add_column :description, String, text: true unless project_columns.include?('description')
      add_column :required_documents, String, text: true unless project_columns.include?('required_documents')
    end
  end

  down do
    project_columns = schema(:projects).map(&:first).map(&:to_s)
    alter_table(:projects) do
      drop_column :required_documents if project_columns.include?('required_documents')
      drop_column :description if project_columns.include?('description')
    end
  end
end
