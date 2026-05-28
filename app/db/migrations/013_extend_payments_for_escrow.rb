Sequel.migration do
  up do
    alter_table(:payments) do
      add_column :milestone_id, :uuid unless column_exists?(:payments, :milestone_id)
      add_column :project_id, :uuid unless column_exists?(:payments, :project_id)
      add_column :recipient_id, :uuid unless column_exists?(:payments, :recipient_id)
      add_column :payment_type, String unless column_exists?(:payments, :payment_type)
      add_column :status, String, default: 'pending' unless column_exists?(:payments, :status)
      add_column :gateway_transaction_id, String unless column_exists?(:payments, :gateway_transaction_id)
    end

    alter_table(:payments) do
      set_column_type :milestone_id, :uuid if column_exists?(:payments, :milestone_id)
      set_column_type :project_id, :uuid if column_exists?(:payments, :project_id)
      set_column_type :recipient_id, :uuid if column_exists?(:payments, :recipient_id)
    end

    existing_foreign_keys = foreign_key_list(:payments)
    unless existing_foreign_keys.any? { |foreign_key| foreign_key[:columns] == [:milestone_id] }
      add_foreign_key :milestone_id, :milestones, type: :uuid, on_delete: :set_null
    end
    unless existing_foreign_keys.any? { |foreign_key| foreign_key[:columns] == [:project_id] }
      add_foreign_key :project_id, :projects, type: :uuid, on_delete: :cascade
    end
    unless existing_foreign_keys.any? { |foreign_key| foreign_key[:columns] == [:recipient_id] }
      add_foreign_key :recipient_id, :accounts, type: :uuid, on_delete: :set_null
    end

    add_index :payments, :milestone_id unless index_exists?(:payments, :milestone_id)
    add_index :payments, :project_id unless index_exists?(:payments, :project_id)
  end

  down do
    alter_table(:payments) do
      drop_column :gateway_transaction_id if column_exists?(:payments, :gateway_transaction_id)
      drop_column :status if column_exists?(:payments, :status)
      drop_column :payment_type if column_exists?(:payments, :payment_type)
      drop_column :recipient_id if column_exists?(:payments, :recipient_id)
      drop_column :project_id if column_exists?(:payments, :project_id)
      drop_column :milestone_id if column_exists?(:payments, :milestone_id)
    end
  end
end
