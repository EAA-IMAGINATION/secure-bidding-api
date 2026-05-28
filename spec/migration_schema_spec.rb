# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require_relative '../app/require_app'

describe 'Schema migrations' do
  it 'create milestone and bid document tables in a fresh database' do
    original_database_url = ENV['DATABASE_URL']
    temp_dir = Dir.mktmpdir

    begin
      ENV['DATABASE_URL'] = "sqlite://#{temp_dir}/fresh.db"
      SecureBidding::Database.connect!
      SecureBidding::Database.migrate!

      _(SecureBidding::DB.table_exists?(:milestones)).must_equal true
      _(SecureBidding::DB.table_exists?(:bid_documents)).must_equal true

      milestone_columns = SecureBidding::DB.schema(:milestones).map(&:first)
      bid_document_columns = SecureBidding::DB.schema(:bid_documents).map(&:first)

      _(milestone_columns).must_include :id
      _(milestone_columns).must_include :project_id
      _(milestone_columns).must_include :assigned_bidder_id
      _(bid_document_columns).must_include :id
      _(bid_document_columns).must_include :bid_id
    ensure
      ENV['DATABASE_URL'] = original_database_url
      SecureBidding::Database.connect!
      FileUtils.remove_entry(temp_dir) if File.exist?(temp_dir)
    end
  end

  it 'repairs a version 12 database that is missing milestone tables' do
    original_database_url = ENV['DATABASE_URL']
    temp_dir = Dir.mktmpdir

    begin
      ENV['DATABASE_URL'] = "sqlite://#{temp_dir}/legacy.db"
      SecureBidding::Database.connect!
      db = SecureBidding::Database.db

      db.create_table(:schema_info) do
        Integer :version, null: false
      end
      db[:schema_info].insert(version: 12)

      db.create_table(:accounts) do
        column :id, :uuid, primary_key: true
      end

      db.create_table(:projects) do
        column :id, :uuid, primary_key: true
      end

      db.create_table(:bid_submissions) do
        column :id, :uuid, primary_key: true
        column :project_id, :uuid, null: false
      end

      db.create_table(:payments) do
        column :id, :uuid, primary_key: true
        column :bid_submission_id, :uuid, null: false
        TrueClass :paid, null: false, default: false
        String :method
        String :reference
        DateTime :paid_at
        DateTime :created_at
        DateTime :updated_at
      end

      SecureBidding::Database.migrate!

      _(db.table_exists?(:milestones)).must_equal true
      _(db.table_exists?(:bid_documents)).must_equal true

      payment_columns = db.schema(:payments).map(&:first)
      _(payment_columns).must_include :milestone_id
      _(payment_columns).must_include :project_id
      _(payment_columns).must_include :recipient_id
      _(payment_columns).must_include :payment_type
      _(payment_columns).must_include :status
      _(payment_columns).must_include :gateway_transaction_id
      _(db.foreign_key_list(:payments).any? { |foreign_key| foreign_key[:columns] == [:milestone_id] }).must_equal true
    ensure
      ENV['DATABASE_URL'] = original_database_url
      SecureBidding::Database.connect!
      FileUtils.remove_entry(temp_dir) if File.exist?(temp_dir)
    end
  end
end
