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
      def self.call(req, app)
        req.on 'bids' do
          handle_create(req, app)
          handle_list_and_show(req, app)
        end
      end

      def self.handle_create(req, app)
        req.post true do
          create_bid(req, app)
        end
      end

      def self.create_bid(req, app)
        data = HttpRequest.new(req).body_data
        result = SecureBidding::Forms::BidsCreateForm.new.call(data)
        unless result.success?
          req.response.status = 400
          return { error: result.errors.to_h }
        end

        bid = build_bid_from_data(result.to_h)
        bid.save

        req.response.status = 201
        { bid_id: bid.id, status: 'created' }
      end

      def self.missing_encrypted_bid_response(req)
        req.response.status = 400
        { error: 'encrypted_bid is required and cannot be empty' }
      end

      def self.build_bid_from_data(data)
        Bid.new(
          contractor: data[:contractor],
          project_id: data[:project_id],
          encrypted_bid: data[:encrypted_bid]
        )
      end

      def self.handle_list_and_show(req, app)
        req.get do
          req.is do
            bid_ids = SecureBidding::Policies::BidPolicy::Scope.new(app.auth_account, Bid).resolve
            { bid_ids: bid_ids }
          end

          req.on String do |id|
            req.get { show_for_id(req, app, id) }
          end
        end
      end

      def self.show_for_id(req, app, id)
        bid = Bid.find(id)
        return not_found_response(req) unless bid

        found_response(app, bid)
      end

      def self.found_response(app, bid)
        app.bid_response(bid, policy: app.bid_policy(bid))
      end

      def self.not_found_response(req)
        req.response.status = 404
        { error: 'Bid not found' }
      end
    end
  end
end
