Sequel.migration do
  up do
    alter_table(:projects) do
      add_column :bidding_deadline, DateTime
    end
  end

  down do
    alter_table(:projects) do
      drop_column :bidding_deadline
    end
  end
end
