# frozen_string_literal: true

module SecureBidding
  module Policies
    class ProjectPolicy < BasePolicy
      RESOURCE = 'projects'

      def index?
        scoped_read?(RESOURCE) && authenticated?
      end

      def show?
        return false unless scoped_read?(RESOURCE)

        admin? || manage? || view_as_awarded_bidder? || published? || pending_owner_request?
      end

      def create?
        scoped_write?(RESOURCE) && authenticated? && !admin? && email_verified?
      end

      def update?
        scoped_write?(RESOURCE) && email_verified? && manage?
      end

      def destroy?
        scoped_write?(RESOURCE) && email_verified? && manage?
      end

      def manage_memberships?
        scoped_write?(RESOURCE) && email_verified? && manage?
      end

      # True only when the account has an explicit project_owner membership or owner collaboration.
      def assigned_owner?
        scoped_write?(RESOURCE) && email_verified? && managed_by_subject?
      end

      # Admin override on a project they do not own (platform management, not ownership).
      def admin_access?
        scoped_write?(RESOURCE) && email_verified? && admin? && !managed_by_subject?
      end

      def accept_ownership?
        scoped_write?(RESOURCE) && email_verified? && pending_owner_request?
      end

      def bid?
        scoped_write?(RESOURCE) && authenticated? && email_verified? && published? && !bidding_closed? && !manage?
      end

      # Published projects still accepting bids (home/catalog listing).
      def available_for_bidding?
        scoped_read?(RESOURCE) && published? && !bidding_closed?
      end

      # Bidder's submission on a project whose bidding window is still open.
      def track_open_bid?
        has_bid_submission? && available_for_bidding?
      end

      def has_bid_submission?
        return false unless authenticated?

        account_id = subject_account_id
        return false if account_id.nil? || record.nil?

        SecureBidding::BidSubmission.first(
          project_id: record.id,
          bidder_account_id: account_id
        ) != nil
      end

      def view_memberships?
        scoped_read?(RESOURCE) && email_verified? && manage?
      end

      def view_bid_submissions?
        return false unless scoped_read?(RESOURCE) && authenticated?

        email_verified? && manage? && bidding_closed?
      end

      def view_bid_count?
        scoped_read?(RESOURCE) && email_verified? && manage?
      end

      def manage_milestones?
        scoped_write?(RESOURCE) && email_verified? && manage?
      end

      def reveal_keys?
        scoped_read?(RESOURCE) && email_verified? && manage? && bidding_closed?
      end

      def award_bid?
        scoped_write?(RESOURCE) && email_verified? && manage? && bidding_closed? && record.state == 'published'
      end

      def request_payment?
        return false unless scoped_write?(RESOURCE) && authenticated? && email_verified?
        return false unless record.state == 'in_progress'
        return false if record.awarded_bid_submission_id.nil?

        awarded = SecureBidding::BidSubmission[record.awarded_bid_submission_id]
        awarded && awarded.bidder_account_id == subject_account_id
      end

      def process_payment?
        scoped_write?(RESOURCE) && email_verified? && manage? &&
          record.state == 'payment_pending' && record.payment_status == 'requested'
      end

      def acknowledge_payment?
        scoped_write?(RESOURCE) && email_verified? && view_as_awarded_bidder? &&
          record.state == 'payment_pending' && record.payment_status == 'in_process'
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
          if account_id.nil? || !email_verified?
            return scope.where(state: 'published').order(:id).all
          end

          published_ids = scope.where(state: 'published').select_map(:id)
          managed_ids = ProjectPolicy.managed_project_ids_for(account_id)
          bidder_ids = SecureBidding::BidSubmission.where(bidder_account_id: account_id).select_map(:project_id)
          awarded_ids = scope.where(Sequel.~(awarded_bid_submission_id: nil)).all.filter_map do |project|
            bid = SecureBidding::BidSubmission[project.awarded_bid_submission_id]
            bid&.bidder_account_id == account_id ? project.id : nil
          end
          visible_ids = (published_ids + managed_ids + awarded_ids + bidder_ids).uniq

          scope.where(id: visible_ids).order(:id).all
        end
      end

      def view_as_awarded_bidder?
        return false unless authenticated?
        return false if record.awarded_bid_submission_id.nil?

        awarded = SecureBidding::BidSubmission[record.awarded_bid_submission_id]
        awarded && awarded.bidder_account_id == subject_account_id
      end

      private

      def published?
        record.state == 'published'
      end

      def bidding_closed?
        self.class.bidding_closed_for?(record)
      end

      def self.bidding_closed_for?(project)
        deadline = project.bidding_deadline
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
