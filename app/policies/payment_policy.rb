# frozen_string_literal: true

module SecureBidding
  # Policy to check if a requester can perform actions on Payment resources
  class PaymentPolicy
    attr_reader :account, :payment

    def initialize(account, payment)
      @account = account
      @payment = payment
    end

    def can_view?
      logged_in? && (is_project_owner? || is_admin?)
    end

    def can_create?
      logged_in?
    end

    def can_update?
      logged_in? && is_admin?
    end

    def summary
      {
        can_view: can_view?,
        can_create: can_create?,
        can_update: can_update?
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

    def is_project_owner?
      return false unless logged_in? && payment&.bid_submission&.project
      account_id = account[:account_id] || account['account_id'] || account.id
      membership = ProjectMembership.where(
        project_id: payment.bid_submission.project.id,
        account_id: account_id
      ).first
      membership&.role&.name == 'project_owner'
    end
  end
end
