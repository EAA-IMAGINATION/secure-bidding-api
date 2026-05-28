Sequel.migration do
  up do
    create_table?(:milestones) do
      column :id, :uuid, primary_key: true
      foreign_key :project_id, :projects, type: :uuid, null: false, on_delete: :cascade
      String :title, null: false
      Text :description
      Integer :budget_cents, null: false
      column :assigned_bidder_id, :uuid
      String :state, null: false, default: 'pending_funding'
      Integer :sequence_order, null: false, default: 1
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
    end

    create_table?(:bid_documents) do
      column :id, :uuid, primary_key: true
      foreign_key :bid_id, :bid_submissions, type: :uuid, null: false, on_delete: :cascade
      String :file_name_secure
      String :file_hash, null: false
      String :storage_path, null: false
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    end

    add_index :milestones, :project_id unless indexes(:milestones).values.any? { |index| index[:columns] == [:project_id] }
    add_index :bid_documents, :bid_id unless indexes(:bid_documents).values.any? { |index| index[:columns] == [:bid_id] }

    payment_columns = schema(:payments).map(&:first)
    payment_foreign_keys = foreign_key_list(:payments)
    if payment_columns.include?(:milestone_id) &&
       !payment_foreign_keys.any? { |foreign_key| foreign_key[:columns] == [:milestone_id] }
      alter_table(:payments) do
        add_foreign_key [:milestone_id], :milestones, on_delete: :set_null
      end
    end
  end

  down do
    drop_table(:bid_documents) if table_exists?(:bid_documents)
    drop_table(:milestones) if table_exists?(:milestones)
  end
end
