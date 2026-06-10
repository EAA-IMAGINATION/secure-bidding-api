# frozen_string_literal: true

Sequel.migration do
  up do
    from(:bid_submissions)
      .where(Sequel.~(bidder_account_id: nil))
      .select_group(:project_id, :bidder_account_id)
      .having { count(:id) > 1 }
      .each do |row|
        duplicates = from(:bid_submissions)
                     .where(project_id: row[:project_id], bidder_account_id: row[:bidder_account_id])
                     .order(Sequel.desc(:created_at), Sequel.desc(:id))
                     .all
        duplicates.drop(1).each(&:delete)
      end

    alter_table(:bid_submissions) do
      add_index %i[project_id bidder_account_id], unique: true
    end
  end

  down do
    alter_table(:bid_submissions) do
      drop_index %i[project_id bidder_account_id]
    end
  end
end
