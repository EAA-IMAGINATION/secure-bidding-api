# frozen_string_literal: true

module SecureBidding
  module Policies
    class BidSubmissionPolicy < BasePolicy
      def index?
        authenticated?
      end

      def show?
        return false unless record&.project

        project_policy.manage? && bidding_closed_for?(record.project)
      end

      def create?
        authenticated?
      end

      class Scope < BasePolicy::Scope
        def resolve
          return scope.order(:id).all if admin?

          account_id = subject_account_id
          return scope.where(false).order(:id).all if account_id.nil?

          managed_ids = ProjectPolicy.managed_project_ids_for(account_id)
          closed_ids = Project.where(id: managed_ids).all.select do |project|
            deadline = project.bidding_deadline
            !deadline.nil? && Time.now >= deadline
          end.map(&:id)

          scope.where(project_id: closed_ids).order(:id).all
        end
      end

      private

      def project_policy
        ProjectPolicy.new(subject, record.project)
      end

      def bidding_closed_for?(project)
        deadline = project.bidding_deadline
        return false if deadline.nil?

        Time.now >= deadline
      end
    end
  end
end
