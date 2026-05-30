# frozen_string_literal: true

module SecureBidding
  module Policies
    class ProjectPolicy < BasePolicy
      def index?
        authenticated?
      end

      def show?
        published? || manage? || admin?
      end

      def create?
        authenticated? && !admin?
      end

      def update?
        manage?
      end

      def destroy?
        manage?
      end

      def manage_memberships?
        manage?
      end

      def accept_ownership?
        authenticated? && pending_owner_request?
      end

      def bid?
        authenticated? && published? && !manage?
      end

      def view_memberships?
        manage?
      end

      def view_bid_submissions?
        return false unless authenticated?

        manage? && bidding_closed?
      end

      # Safe count before deadline; no bid payloads.
      def view_bid_count?
        manage?
      end

      def manage_milestones?
        manage?
      end

      # Used by other policies (payments, bid submissions).
      def manage?
        admin? || managed_by_subject?
      end

      def self.managed_project_ids_for(account_id)
          owner_role = SecureBidding::Role.ensure_role('project_owner')
          membership_ids = if owner_role.nil?
                             []
                           else
                             SecureBidding::ProjectMembership
                               .where(account_id: account_id, role_id: owner_role.id)
                               .select_map(:project_id)
                           end

          collaboration_ids = SecureBidding::AccountProject
                                .where(account_id: account_id)
                                .where(Sequel.|(
                                  { collaboration_role: 'owner' },
                                  { collaboration_role: 'pending_owner' }
                                ))
                                .select_map(:project_id)

          (membership_ids + collaboration_ids).uniq
      end

      class Scope < BasePolicy::Scope
        def resolve
          if admin?
            return scope.order(:id).all
          end

          account_id = subject_account_id
          if account_id.nil?
            return scope.where(state: 'published').order(:id).all
          end

          published_ids = scope.where(state: 'published').select_map(:id)
          managed_ids = ProjectPolicy.managed_project_ids_for(account_id)
          visible_ids = (published_ids + managed_ids).uniq

          scope.where(id: visible_ids).order(:id).all
        end
      end

      private

      def published?
        record.state == 'published'
      end

      def bidding_closed?
        deadline = record.bidding_deadline
        return false if deadline.nil?

        Time.now >= deadline
      end

      def managed_by_subject?
        return false unless authenticated?
        return false if record.nil?

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
        return false if account_id.nil? || record.nil?

        collaboration = SecureBidding::AccountProject.first(account_id: account_id, project_id: record.id)
        !collaboration.nil? && collaboration.collaboration_role == 'pending_owner'
      end
    end
  end
end
