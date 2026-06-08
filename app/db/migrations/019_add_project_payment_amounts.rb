# frozen_string_literal: true

Sequel.migration do
  up do
    project_columns = schema(:projects).map(&:first).map(&:to_s)
    alter_table(:projects) do
      add_column :awarded_bid_amount_cents, Integer unless project_columns.include?('awarded_bid_amount_cents')
      add_column :payment_amount_cents, Integer unless project_columns.include?('payment_amount_cents')
    end
  end

  down do
    project_columns = schema(:projects).map(&:first).map(&:to_s)
    alter_table(:projects) do
      drop_column :payment_amount_cents if project_columns.include?('payment_amount_cents')
      drop_column :awarded_bid_amount_cents if project_columns.include?('awarded_bid_amount_cents')
    end
  end
end
