# frozen_string_literal: true

require 'minitest/autorun'
require 'base64'
require_relative '../app/models/bid'

# rubocop:disable Metrics/BlockLength
describe 'SecureBidding::Bid' do
  def sample_project_id
    '11111111-1111-4111-8111-111111111111'
  end

  def sample_encrypted_bid
    Base64.strict_encode64('encrypted_data_here')
  end

  before do
    Dir.glob('app/db/store/*.json').each { |f| File.delete(f) }
  end

  describe 'instance methods' do
    it 'saves a bid with encrypted storage' do
      bid = SecureBidding::Bid.new(
        contractor: 'ABC Corp',
        project_id: sample_project_id,
        encrypted_bid: sample_encrypted_bid
      )
      bid.save

      files = Dir.glob('app/db/store/*.json')
      _(files.any?).must_equal true

      raw = File.read(files.first)
      _(raw).wont_include 'ABC Corp'
      _(raw).wont_include sample_project_id
    end
  end

  describe 'class methods' do
    it 'finds a bid by id' do
      bid = SecureBidding::Bid.new(
        contractor: 'Test Corp',
        project_id: sample_project_id,
        encrypted_bid: Base64.strict_encode64('test_encrypted_data')
      )
      bid.save

      found_bid = SecureBidding::Bid.find(bid.id)
      _(found_bid).wont_be_nil
      _(found_bid.id).must_equal bid.id
      _(found_bid.contractor).must_equal 'Test Corp'
      _(found_bid.project_id).must_equal sample_project_id
    end

    it 'returns nil for non-uuid id' do
      found_bid = SecureBidding::Bid.find('../../../etc/passwd')
      _(found_bid).must_be_nil
    end

    it 'returns nil for non-existent bid' do
      found_bid = SecureBidding::Bid.find('00000000-0000-4000-8000-000000000000')
      _(found_bid).must_be_nil
    end

    it 'returns all bid ids' do
      bid1 = SecureBidding::Bid.new(
        contractor: 'Corp A',
        project_id: sample_project_id,
        encrypted_bid: Base64.strict_encode64('data1')
      )
      bid1.save

      bid2 = SecureBidding::Bid.new(
        contractor: 'Corp B',
        project_id: '22222222-2222-4222-8222-222222222222',
        encrypted_bid: Base64.strict_encode64('data2')
      )
      bid2.save

      all_ids = SecureBidding::Bid.all
      _(all_ids).must_include bid1.id
      _(all_ids).must_include bid2.id
    end

    it 'returns empty array when no bids exist' do
      all_ids = SecureBidding::Bid.all
      _(all_ids).must_be_empty
    end
  end
end
# rubocop:enable Metrics/BlockLength
