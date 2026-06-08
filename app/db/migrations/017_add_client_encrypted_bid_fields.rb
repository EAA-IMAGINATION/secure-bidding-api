# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:bid_submissions) do
      add_column :encrypted_bid_amount, String, text: true
      add_column :encrypted_proposal_text, String, text: true
      set_column_allow_null :secure_encrypted_bid, true
    end
  end

  down do
    alter_table(:bid_submissions) do
      drop_column :encrypted_proposal_text
      drop_column :encrypted_bid_amount
      set_column_allow_null :secure_encrypted_bid, false
    end
  end
end
