# frozen_string_literal: true

module SecureBidding
  # Policy to check if a requester can perform actions on an Account resource
  class AccountPolicy
    attr_reader :requester, :account

    def initialize(requester, account)
      @requester = requester
      @account = account
    end

    def can_view?
      logged_in? && (is_owner? || is_admin?)
    end

    def can_update?
      logged_in? && (is_owner? || is_admin?)
    end

    def can_delete?
      logged_in? && is_admin?
    end

    def can_list?
      logged_in? && is_admin?
    end

    def can_search?
      logged_in?
    end

    def can_assign_role?
      logged_in? && is_admin?
    end

    def summary
      {
        can_view: can_view?,
        can_update: can_update?,
        can_delete: can_delete?,
        can_list: can_list?,
        can_search: can_search?,
        can_assign_role: can_assign_role?
      }
    end

    private

    def logged_in?
      !requester.nil?
    end

    def is_admin?
      return false unless logged_in?
      role = requester[:system_role] || requester['system_role']
      role == 'admin'
    end

    def is_owner?
      return false unless logged_in? && account
      requester_id = requester[:account_id] || requester['account_id'] || requester.id
      requester_id == account.id
    end
  end
end
