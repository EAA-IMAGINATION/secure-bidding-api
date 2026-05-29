# frozen_string_literal: true

module SecureBidding
  module Policies
    class BidSubmissionPolicy < BasePolicy
      def index?
        true
      end

      def show?
        true
      end

      def create?
        authenticated?
      end

      def summary
        super
      end

      class Scope < BasePolicy::Scope
        def resolve
          scope.order(:id).all
        end
      end
    end
  end
end
