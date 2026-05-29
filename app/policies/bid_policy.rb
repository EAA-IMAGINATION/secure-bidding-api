# frozen_string_literal: true

module SecureBidding
  module Policies
    class BidPolicy < BasePolicy
      def index?
        true
      end

      def show?
        true
      end

      def create?
        true
      end

      class Scope < BasePolicy::Scope
        def resolve
          scope.all
        end
      end
    end
  end
end
