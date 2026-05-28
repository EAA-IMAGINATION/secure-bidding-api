Sequel.migration do
  up do
    # Try to alter payments table; ignore duplicate-column errors to support local variations
    begin
      alter_table(:payments) do
        add_column :milestone_id, String
        add_foreign_key :milestone_id, :milestones, type: String, on_delete: :set_null
        add_column :project_id, String
        add_foreign_key :project_id, :projects, type: String, on_delete: :cascade
        add_column :recipient_id, String
        add_foreign_key :recipient_id, :accounts, type: String, on_delete: :set_null
        add_column :payment_type, String
        add_column :status, String, default: 'pending'
        add_column :gateway_transaction_id, String
      end

      add_index :payments, :milestone_id
      add_index :payments, :project_id
    rescue Sequel::DatabaseError => e
      # Common reason: column or index already exists in local DB; warn and continue
      warn "Migration 013: warning - #{e.message}"
    end
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
