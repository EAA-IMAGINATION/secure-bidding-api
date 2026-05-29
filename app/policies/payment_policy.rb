# frozen_string_literal: true

module SecureBidding
  module Policies
    class PaymentPolicy < BasePolicy
      def index?
        true
      end

      def show?
        true
      end

      def create?
        true
      end

      def update?
        true
      end

      class Scope < BasePolicy::Scope
        def resolve
          scope.order(:id).all
        end
      end
    end
  end
end
