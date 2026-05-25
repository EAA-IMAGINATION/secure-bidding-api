# frozen_string_literal: true

module SecureBidding
  # Policy to check if a requester can view or create bid submissions
  class BidSubmissionPolicy
    attr_reader :account, :bid_submission

    def initialize(account, bid_submission)
      @account = account
      @bid_submission = bid_submission
    end

    def can_view?
      logged_in? && project_revealed? && (is_project_owner? || is_admin?)
    end

    def can_create?
      logged_in? && project_published? && !is_project_owner? && !is_admin?
    end

    def can_list?
      logged_in? && is_admin?
    end

    def summary
      {
        can_view: can_view?,
        can_create: can_create?,
        can_list: can_list?
      }
    end

    private

    def logged_in?
      !account.nil?
    end

    def is_admin?
      return false unless logged_in?
      role = account[:system_role] || account['system_role']
      role == 'admin'
    end

    def project_published?
      bid_submission&.project&.state == 'published'
    end

    def project_revealed?
      bid_submission.nil? || bid_submission.project.nil? || bid_submission.project.submission_deadline_passed?
    end

    def is_project_owner?
      return false unless logged_in? && bid_submission&.project
      account_id = account[:account_id] || account['account_id'] || account.id
      membership = ProjectMembership.where(project_id: bid_submission.project.id, account_id: account_id).first
      membership&.role&.name == 'project_owner'
    end
  end
end
