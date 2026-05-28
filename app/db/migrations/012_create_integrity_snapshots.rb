Sequel.migration do
  up do
    create_table(:integrity_snapshots) do
      String :id, primary_key: true
      foreign_key :project_id, :projects, type: String, null: false, unique: true, on_delete: :cascade
      String :canonical_hash, null: false
      DateTime :snapshot_taken_at, null: false
    end

    add_index :integrity_snapshots, :project_id
  end

  down do
    drop_table(:integrity_snapshots)
  end
end
