# frozen_string_literal: true

module SecureBidding
  module Routes
    module Bids
      def self.call(r, app)
        r.on 'bids' do
          # POST /api/v1/bids - Create a new bid
          r.post true do
            data = HttpRequest.new(r).body_data

            encrypted_bid = data[:encrypted_bid] || data['encrypted_bid']
            if encrypted_bid.nil? || encrypted_bid.to_s.strip.empty?
              r.response.status = 400
              { error: 'encrypted_bid is required and cannot be empty' }
            else
              bid = Bid.new(
                contractor: (data[:contractor] || data['contractor']),
                project_id: (data[:project_id] || data['project_id']),
                encrypted_bid: encrypted_bid
              )
              bid.save

              r.response.status = 201
              { bid_id: bid.id, status: 'created' }
            end
          end

          # GET /api/v1/bids - Get all bid IDs
          r.get do
            r.is do
              bid_ids = Bid.all
              { bid_ids: bid_ids }
            end

            # GET /api/v1/bids/:id.json - Get a specific bid
            r.on String do |id|
              r.get do
                bid = Bid.find(id)
                if bid
                  {
                    id: bid.id,
                    contractor: bid.contractor,
                    project_id: bid.project_id,
                    encrypted_bid: bid.encrypted_bid
                  }
                else
                  r.response.status = 404
                  { error: 'Bid not found' }
                end
              end
            end
          end
        end
      end
    end
  end
end
