require 'json'
require 'securerandom'

module SecureBidding
  # Represents a bid in the secure bidding system
  class Bid
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
      JSON.generate({
        id: @id,
        contractor: @contractor,
        project_id: @project_id,
        encrypted_bid: @encrypted_bid
      })
    end

    def save
      File.write("app/db/store/#{id}.json", to_json)
    end

    # Class methods
    def self.find(id)
      file_path = "app/db/store/#{id}.json"
      return nil unless File.exist?(file_path)

      data = JSON.parse(File.read(file_path))
      bid = allocate
      bid.instance_variable_set(:@id, data['id'])
      bid.instance_variable_set(:@contractor, data['contractor'])
      bid.instance_variable_set(:@project_id, data['project_id'])
      bid.instance_variable_set(:@encrypted_bid, data['encrypted_bid'])
      bid
    end

    def self.all
      Dir.glob('app/db/store/*.json').map do |file|
        File.basename(file, '.json')
      end
    end
  end
end
