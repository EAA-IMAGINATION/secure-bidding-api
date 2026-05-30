# frozen_string_literal: true

module SecureBidding
  module Policies
    class MilestonePolicy < BasePolicy
      def show?
        project_policy.manage?
      end

      def fund_escrow?
        project_policy.manage?
      end

      def release_escrow?
        project_policy.manage?
      end

      private

      def project_policy
        ProjectPolicy.new(subject, record.project)
      end
    end
  end
end
