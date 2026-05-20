# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../app/models/bid'

# rubocop:disable Metrics/BlockLength
describe 'SecureBidding::Bid' do
  before do
    # Clean up store before each test
    Dir.glob('app/db/store/*.json').each { |f| File.delete(f) }
  end

  describe 'instance methods' do
    it 'should save a bid and create a file in the store' do
      bid = SecureBidding::Bid.new(
        contractor: 'ABC Corp',
        project_id: 'proj-123',
        encrypted_bid: 'encrypted_data_here'
      )
      bid.save

      # Check if any file was created in app/db/store/
      files = Dir.glob('app/db/store/*.json')
      _(files.any?).must_equal true
    end
  end

  describe 'class methods' do
    it 'should find a bid by id' do
      # Create and save a bid
      bid = SecureBidding::Bid.new(
        contractor: 'Test Corp',
        project_id: 'proj-456',
        encrypted_bid: 'test_encrypted_data'
      )
      bid.save

      # Find the bid
      found_bid = SecureBidding::Bid.find(bid.id)
      _(found_bid).wont_be_nil
      _(found_bid.id).must_equal bid.id
      _(found_bid.contractor).must_equal 'Test Corp'
      _(found_bid.project_id).must_equal 'proj-456'
      _(found_bid.encrypted_bid).must_equal 'test_encrypted_data'
    end

    it 'should return nil for non-existent bid' do
      found_bid = SecureBidding::Bid.find('non-existent-id')
      _(found_bid).must_be_nil
    end

    it 'should return all bid ids' do
      # Create multiple bids
      bid1 = SecureBidding::Bid.new(
        contractor: 'Corp A',
        project_id: 'proj-1',
        encrypted_bid: 'data1'
      )
      bid1.save

      bid2 = SecureBidding::Bid.new(
        contractor: 'Corp B',
        project_id: 'proj-2',
        encrypted_bid: 'data2'
      )
      bid2.save

      # Get all IDs
      all_ids = SecureBidding::Bid.all
      _(all_ids).must_be_kind_of Array
      _(all_ids.length).must_equal 2
      _(all_ids).must_include bid1.id
      _(all_ids).must_include bid2.id
    end

    it 'should return empty array when no bids exist' do
      all_ids = SecureBidding::Bid.all
      _(all_ids).must_be_kind_of Array
      _(all_ids).must_be_empty
    end
  end
end
# rubocop:enable Metrics/BlockLength
