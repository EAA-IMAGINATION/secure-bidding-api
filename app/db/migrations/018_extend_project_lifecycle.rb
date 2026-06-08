# frozen_string_literal: true

Sequel.migration do
  up do
    bid_columns = schema(:bid_submissions).map(&:first).map(&:to_s)
    alter_table(:bid_submissions) do
      add_column :bidder_account_id, :uuid unless bid_columns.include?('bidder_account_id')
      add_column :encrypted_document, String, text: true unless bid_columns.include?('encrypted_document')
      add_column :document_file_name, String unless bid_columns.include?('document_file_name')
      add_column :document_file_hash, String unless bid_columns.include?('document_file_hash')
    end

    project_columns = schema(:projects).map(&:first).map(&:to_s)
    alter_table(:projects) do
      add_column :awarded_bid_submission_id, :uuid unless project_columns.include?('awarded_bid_submission_id')
      add_column :payment_status, String, null: false, default: 'none' unless project_columns.include?('payment_status')
    end
  end

  down do
    project_columns = schema(:projects).map(&:first).map(&:to_s)
    alter_table(:projects) do
      drop_column :payment_status if project_columns.include?('payment_status')
      drop_column :awarded_bid_submission_id if project_columns.include?('awarded_bid_submission_id')
    end

    bid_columns = schema(:bid_submissions).map(&:first).map(&:to_s)
    alter_table(:bid_submissions) do
      drop_column :document_file_hash if bid_columns.include?('document_file_hash')
      drop_column :document_file_name if bid_columns.include?('document_file_name')
      drop_column :encrypted_document if bid_columns.include?('encrypted_document')
      drop_column :bidder_account_id if bid_columns.include?('bidder_account_id')
    end
  end
end
