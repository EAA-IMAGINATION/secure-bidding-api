# frozen_string_literal: true

module SecureBidding
  module Policies
    class AccountPolicy < BasePolicy
      def index?
        admin?
      end

      def show?
        true
      end

      def create?
        true
      end

      def update?
        admin? || own_record?
      end

      def destroy?
        admin?
      end

      def search?
        admin?
      end

      def assign_system_role?
        admin?
      end

      def resend_verification?
        admin? || own_record?
      end

      def summary
        super.merge(capabilities: subject_capabilities)
      end

      class Scope < BasePolicy::Scope
        def resolve
          return scope.order(:id).all if admin?

          []
        end
      end

      private

      def own_record?
        subject_account_id == record.id
      end

      def subject_capabilities
        return {} if subject.nil?

        account = subject.respond_to?(:capabilities) ? subject : nil
        return account.capabilities if account

        {
          admin: admin?,
          system_admin: subject_has_system_role?('system_admin'),
          project_owner: subject_has_system_role?('project_owner'),
          bidder: subject_has_system_role?('bidder'),
          can_manage_accounts: admin?,
          can_assign_system_roles: admin?,
          can_create_projects: admin? || subject_has_system_role?('project_owner')
        }
      end
    end
  end
end
