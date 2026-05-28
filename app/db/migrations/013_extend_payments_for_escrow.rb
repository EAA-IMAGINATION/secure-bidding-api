Sequel.migration do
  up do
    payment_columns = schema(:payments).map(&:first)
    has_milestone_id = payment_columns.include?(:milestone_id)
    has_project_id = payment_columns.include?(:project_id)
    has_recipient_id = payment_columns.include?(:recipient_id)
    has_payment_type = payment_columns.include?(:payment_type)
    has_status = payment_columns.include?(:status)
    has_gateway_transaction_id = payment_columns.include?(:gateway_transaction_id)

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
      alter_table(:payments) do
        add_foreign_key [:milestone_id], :milestones, on_delete: :set_null
      end
    end
    unless existing_foreign_keys.any? { |foreign_key| foreign_key[:columns] == [:project_id] }
      alter_table(:payments) do
        add_foreign_key [:project_id], :projects, on_delete: :cascade
      end
    end
    unless existing_foreign_keys.any? { |foreign_key| foreign_key[:columns] == [:recipient_id] }
      alter_table(:payments) do
        add_foreign_key [:recipient_id], :accounts, on_delete: :set_null
      end
    end

    add_index :payments, :milestone_id unless index_exists?(:payments, :milestone_id)
    add_index :payments, :project_id unless index_exists?(:payments, :project_id)
  end

  down do
    payment_columns = schema(:payments).map(&:first)

    alter_table(:payments) do
      drop_column :gateway_transaction_id if payment_columns.include?(:gateway_transaction_id)
      drop_column :status if payment_columns.include?(:status)
      drop_column :payment_type if payment_columns.include?(:payment_type)
      drop_column :recipient_id if payment_columns.include?(:recipient_id)
      drop_column :project_id if payment_columns.include?(:project_id)
      drop_column :milestone_id if payment_columns.include?(:milestone_id)
    end
  end
end
