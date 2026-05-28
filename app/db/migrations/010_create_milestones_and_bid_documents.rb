Sequel.migration do
  up do
    create_table(:milestones) do
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

    create_table(:bid_documents) do
      column :id, :uuid, primary_key: true
      foreign_key :bid_id, :bid_submissions, type: :uuid, null: false, on_delete: :cascade
      String :file_name_secure
      String :file_hash, null: false
      String :storage_path, null: false
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
    end

    add_index :milestones, :project_id
    add_index :bid_documents, :bid_id
  end

  down do
    drop_table(:bid_documents)
    drop_table(:milestones)
  end
end
