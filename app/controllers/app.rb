require 'roda'
require 'json'
require_relative '../models/bid'

module SecureBidding
  class App < Roda
    plugin :json
    plugin :halt

    route do |r|
      # Root route - health check
      r.root do
        { message: 'Secure Bidding API v1.0', status: 'ok' }
      end

      r.on 'api' do
        r.on 'v1' do
          r.on 'bids' do
            # POST /api/v1/bids - Create a new bid
            r.post do
              # Parse JSON request body
              data = JSON.parse(request.body.read)

              # Validate encrypted_bid is present and not empty
              encrypted_bid = data['encrypted_bid']
              if encrypted_bid.nil? || encrypted_bid.to_s.strip.empty?
                response.status = 400
                { error: 'encrypted_bid is required and cannot be empty' }
              else
                # Create and save the bid
                bid = Bid.new(
                  contractor: data['contractor'],
                  project_id: data['project_id'],
                  encrypted_bid: encrypted_bid
                )
                bid.save

                # Return 201 Created with bid_id and status
                response.status = 201
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
                    response.status = 404
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
end
