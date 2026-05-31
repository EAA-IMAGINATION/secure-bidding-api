# frozen_string_literal: true

module SecureBidding
  module Policies
    class MilestonePolicy < BasePolicy
      RESOURCE = 'milestones'

      def show?
        scoped_read?(RESOURCE) && project_policy.manage?
      end

      def fund_escrow?
        scoped_write?(RESOURCE) && project_policy.manage?
      end

      def release_escrow?
        scoped_write?(RESOURCE) && project_policy.manage?
      end

      private

      def project_policy
        ProjectPolicy.new(subject, record.project, auth_scope: auth_scope)
      end
    end
  end
end
