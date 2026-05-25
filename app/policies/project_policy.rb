# frozen_string_literal: true

module SecureBidding
  # Policy to check if an account can perform actions on a project
  class ProjectPolicy
    attr_reader :account, :project

    def initialize(account, project)
      @account = account
      @project = project
    end

    def can_view?
      published? || is_owner? || is_collaborator? || is_admin?
    end

    def can_create?
      logged_in? && !is_admin?
    end

    def can_edit?
      logged_in? && (is_owner? || is_admin?)
    end

    alias can_update? can_edit?

    def can_delete?
      logged_in? && (is_owner? || is_admin?)
    end

    def can_view_memberships?
      logged_in? && (is_owner? || is_collaborator? || is_admin?)
    end

    def can_assign_role?
      logged_in? && (is_owner? || is_admin?)
    end

    def can_submit_bid?
      logged_in? && published? && !is_owner? && !is_admin?
    end

    def can_view_bid_count?
      logged_in? && (is_owner? || is_admin?) && !bids_revealed?
    end

    def can_view_bid_submissions?
      logged_in? && (is_owner? || is_admin?) && bids_revealed?
    end

    def summary
      {
        can_view: can_view?,
        can_create: can_create?,
        can_edit: can_edit?,
        can_delete: can_delete?,
        can_view_memberships: can_view_memberships?,
        can_assign_role: can_assign_role?,
        can_submit_bid: can_submit_bid?,
        can_view_bid_count: can_view_bid_count?,
        can_view_bid_submissions: can_view_bid_submissions?
      }
    end

    private

    def logged_in?
      !account.nil?
    end

    def published?
      project&.state == 'published'
    end

    def bids_revealed?
      project.nil? || project.submission_deadline_passed?
    end

    def is_admin?
      return false unless logged_in?
      role = account[:system_role] || account['system_role']
      role == 'admin'
    end

    def is_owner?
      return false unless logged_in? && project
      account_id = account[:account_id] || account['account_id'] || account.id
      membership = ProjectMembership.where(project_id: project.id, account_id: account_id).first
      membership&.role&.name == 'project_owner'
    end

    def is_collaborator?
      return false unless logged_in? && project
      account_id = account[:account_id] || account['account_id'] || account.id
      membership = ProjectMembership.where(project_id: project.id, account_id: account_id).first
      !membership.nil?
    end

    # Policy Scope for filtering queries
    class Scope
      attr_reader :account, :scope

      def initialize(account, scope)
        @account = account
        @scope = scope
      end

      def resolve
        if account.nil?
          scope.where(state: 'published')
        elsif is_admin?
          scope
        else
          account_id = account[:account_id] || account['account_id'] || account.id
          # Sequel.or combines conditions with OR
          scope.where(
            Sequel.or(
              state: 'published',
              id: ProjectMembership.where(account_id: account_id).select(:project_id)
            )
          )
        end
      end

      private

      def is_admin?
        return false if account.nil?
        role = account[:system_role] || account['system_role']
        role == 'admin'
      end
    end
  end
end
