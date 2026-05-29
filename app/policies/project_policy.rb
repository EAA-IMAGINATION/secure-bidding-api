# frozen_string_literal: true

module SecureBidding
  module Policies
    class ProjectPolicy < BasePolicy
      def index?
        true
      end

      def show?
        published? || managed_by_subject?
      end

      def create?
        authenticated?
      end

      def update?
        admin? || managed_by_subject?
      end

      def destroy?
        admin? || managed_by_subject?
      end

      def manage_memberships?
        admin? || managed_by_subject?
      end

      def accept_ownership?
        authenticated? && pending_owner_request?
      end

      def bid?
        authenticated? && published? && !managed_by_subject?
      end

      def view_memberships?
        true
      end

      def view_bid_submissions?
        true
      end

      class Scope < BasePolicy::Scope
        def resolve
          scope.where(state: 'published').order(:id).all
        end
      end

      private

      def published?
        record.state == 'published'
      end

      def managed_by_subject?
        return false unless authenticated?

        owner_role = SecureBidding::Role.ensure_role('project_owner')
        return false if owner_role.nil?

        account_id = subject_account_id
        return false if account_id.nil?

        owner_membership = SecureBidding::ProjectMembership.first(
          account_id: account_id,
          project_id: record.id,
          role_id: owner_role.id
        )
        return true unless owner_membership.nil?

        collaboration = SecureBidding::AccountProject.first(account_id: account_id, project_id: record.id)
        !collaboration.nil? && collaboration.collaboration_role == 'owner'
      end

      def pending_owner_request?
        account_id = subject_account_id
        return false if account_id.nil?

        collaboration = SecureBidding::AccountProject.first(account_id: account_id, project_id: record.id)
        !collaboration.nil? && collaboration.collaboration_role == 'pending_owner'
      end
    end
  end
end
