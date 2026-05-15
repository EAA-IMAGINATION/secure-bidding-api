# frozen_string_literal: true

module SecureBidding
  module Routes
    # Routes related to bid creation and retrieval.
    # Extracted from the main controller to keep routing concerns separated.
    module Bids
      # Entry point called by the application routing setup.
      # Parameters:
      # - req: the Roda request routing object
      # - _app: the application class (unused)
      def self.call(req, _app)
        req.on 'bids' do
          handle_create(req)
          handle_list_and_show(req)
        end
      end

      def self.handle_create(req)
        req.post true do
          create_bid(req)
        end
      end

      def self.create_bid(req)
        data = HttpRequest.new(req).body_data
        encrypted_bid = data[:encrypted_bid] || data['encrypted_bid']

        if encrypted_bid.nil? || encrypted_bid.to_s.strip.empty?
          missing_encrypted_bid_response(req)
        else
          bid = build_bid_from_data(data, encrypted_bid)
          bid.save

          req.response.status = 201
          { bid_id: bid.id, status: 'created' }
        end
      end

      def self.missing_encrypted_bid_response(req)
        req.response.status = 400
        { error: 'encrypted_bid is required and cannot be empty' }
      end

      def self.build_bid_from_data(data, encrypted_bid)
        Bid.new(
          contractor: data[:contractor] || data['contractor'],
          project_id: data[:project_id] || data['project_id'],
          encrypted_bid: encrypted_bid
        )
      end

      def self.handle_list_and_show(req)
        req.get do
          handle_list(req)
          handle_show(req)
        end
      end

      def self.handle_list(req)
        req.is do
          bid_ids = Bid.all
          { bid_ids: bid_ids }
        end
      end

      def self.handle_show(req)
        req.on String do |id|
          req.get { show_for_id(req, id) }
        end
      end

      def self.show_for_id(req, id)
        bid = Bid.find(id)
        return not_found_response(req) unless bid

        found_response(bid)
      end

      def self.found_response(bid)
        {
          id: bid.id,
          contractor: bid.contractor,
          project_id: bid.project_id,
          encrypted_bid: bid.encrypted_bid
        }
      end

      def self.not_found_response(req)
        req.response.status = 404
        { error: 'Bid not found' }
      end
    end
  end
end
