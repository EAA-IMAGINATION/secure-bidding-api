# frozen_string_literal: true

module SecureBidding
  module Routes
    # Routes related to legacy file-backed bid creation and retrieval.
    module Bids
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
        return unauthorized_response(req) unless app.auth_account

        data = HttpRequest.new(req).body_data
        result = SecureBidding::Forms::BidsCreateForm.new.call(data)
        unless result.success?
          req.response.status = 400
          return { error: result.errors.to_h }
        end

        bid = build_bid_from_data(result.to_h)
        unless app.bid_policy(bid).create?
          return forbidden_response(req, 'Forbidden: only project owners or admins can create legacy bids')
        end

        bid.save

        req.response.status = 201
        { bid_id: bid.id, status: 'created' }
      end

      def self.handle_list_and_show(req, app)
        req.get do
          req.is do
            list_bids(req, app)
          end

          req.on String do |id|
            req.get { show_for_id(req, app, id) }
          end
        end
      end

      def self.list_bids(req, app)
        return unauthorized_response(req) unless app.auth_account
        return forbidden_response(req, 'Forbidden') unless app.bid_policy(nil).index?

        bid_ids = SecureBidding::Policies::BidPolicy::Scope.new(app.auth_account, Bid).resolve
        { bid_ids: bid_ids }
      end

      def self.show_for_id(req, app, id)
        return unauthorized_response(req) unless app.auth_account

        bid = Bid.find(id)
        return not_found_response(req) unless bid
        return not_found_response(req) unless app.bid_policy(bid).show?

        found_response(app, bid)
      end

      def self.found_response(app, bid)
        app.bid_response(bid, policy: app.bid_policy(bid))
      end

      def self.not_found_response(req)
        req.response.status = 404
        { error: 'Bid not found' }
      end

      def self.unauthorized_response(req)
        req.response.status = 401
        { error: 'Login required' }
      end

      def self.forbidden_response(req, message = 'Forbidden')
        req.response.status = 403
        { error: message }
      end

      def self.build_bid_from_data(data)
        Bid.new(
          contractor: data[:contractor],
          project_id: data[:project_id],
          encrypted_bid: data[:encrypted_bid]
        )
      end
    end
  end
end
