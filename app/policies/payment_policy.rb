# frozen_string_literal: true

module SecureBidding
  module Policies
    class PaymentPolicy < BasePolicy
      RESOURCE = 'payments'

      def index?
        scoped_read?(RESOURCE) && admin?
      end

      def show?
        scoped_read?(RESOURCE) && linked_project_manage?
      end

      def create?
        scoped_write?(RESOURCE) && linked_project_manage?
      end

      def update?
        scoped_write?(RESOURCE) && linked_project_manage?
      end

      class Scope < BasePolicy::Scope
        def resolve
          return scope.order(:id).all if admin?

          account_id = subject_account_id
          return scope.where(false).order(:id).all if account_id.nil?

          managed_ids = ProjectPolicy.managed_project_ids_for(account_id)
          submission_ids = SecureBidding::BidSubmission.where(project_id: managed_ids).select_map(:id)
          scope.where(bid_submission_id: submission_ids).order(:id).all
        end
      end

      private

      def linked_project_manage?
        submission = record.bid_submission
        return false unless submission&.project

        ProjectPolicy.new(subject, submission.project, auth_scope: auth_scope).manage?
      end
    end
  end
end
