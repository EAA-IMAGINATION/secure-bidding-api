# frozen_string_literal: true

require 'json'
require 'securerandom'

require_relative '../lib/secure_db'

module SecureBidding
  # Represents a legacy file-backed bid in the secure bidding system.
  class Bid
    UUID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i.freeze
    STORAGE_DIR = 'app/db/store'

    attr_accessor :id, :contractor, :project_id, :encrypted_bid

    def initialize(contractor:, project_id:, encrypted_bid:)
      @id = new_id
      @contractor = contractor
      @project_id = project_id
      @encrypted_bid = encrypted_bid
    end

    def new_id
      SecureRandom.uuid
    end

    def to_json(*_args)
      JSON.generate(
        {
          id: @id,
          contractor: @contractor,
          project_id: @project_id,
          encrypted_bid: @encrypted_bid
        }
      )
    end

    def save
      raise ArgumentError, 'bid id is not a valid UUID' unless self.class.valid_uuid?(@id)

      File.write(storage_path, SecureDB.encrypt(to_json))
    end

    def self.find(id)
      return nil unless valid_uuid?(id)

      file_path = storage_path_for(id)
      return nil unless File.exist?(file_path)

      load_from_storage(File.read(file_path))
    end

    def self.all
      Dir.glob("#{STORAGE_DIR}/*.json").map do |file|
        File.basename(file, '.json')
      end.select { |bid_id| valid_uuid?(bid_id) }
    end

    def self.valid_uuid?(value)
      value.to_s.match?(UUID_FORMAT)
    end

    def self.storage_path_for(id)
      "#{STORAGE_DIR}/#{id}.json"
    end

    def self.load_from_storage(raw)
      payload_json =
        begin
          SecureDB.decrypt(raw)
        rescue StandardError
          raw
        end

      data = JSON.parse(payload_json)
      bid = allocate
      bid.instance_variable_set(:@id, data['id'])
      bid.instance_variable_set(:@contractor, data['contractor'])
      bid.instance_variable_set(:@project_id, data['project_id'])
      bid.instance_variable_set(:@encrypted_bid, data['encrypted_bid'])
      bid
    rescue JSON::ParserError, ArgumentError
      nil
    end

    private

    def storage_path
      self.class.storage_path_for(@id)
    end
  end
end
