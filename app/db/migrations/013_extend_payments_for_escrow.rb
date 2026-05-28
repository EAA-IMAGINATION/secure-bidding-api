Sequel.migration do
  up do
    has_milestone_id = column_exists?(:payments, :milestone_id)
    has_project_id = column_exists?(:payments, :project_id)
    has_recipient_id = column_exists?(:payments, :recipient_id)
    has_payment_type = column_exists?(:payments, :payment_type)
    has_status = column_exists?(:payments, :status)
    has_gateway_transaction_id = column_exists?(:payments, :gateway_transaction_id)

    existing_foreign_keys = foreign_key_list(:payments)

    alter_table(:payments) do
      add_column :milestone_id, :uuid unless has_milestone_id
      add_column :project_id, :uuid unless has_project_id
      add_column :recipient_id, :uuid unless has_recipient_id
      add_column :payment_type, String unless has_payment_type
      add_column :status, String, default: 'pending' unless has_status
      add_column :gateway_transaction_id, String unless has_gateway_transaction_id
    end

    if has_milestone_id
      alter_table(:payments) do
        set_column_type :milestone_id, :uuid
      end
    end

    if has_project_id
      alter_table(:payments) do
        set_column_type :project_id, :uuid
      end
    end

    if has_recipient_id
      alter_table(:payments) do
        set_column_type :recipient_id, :uuid
      end
    end

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
