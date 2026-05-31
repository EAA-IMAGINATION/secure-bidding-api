# frozen_string_literal: true

module SecureBidding
  module Policies
    class AccountPolicy < BasePolicy
      RESOURCE = 'accounts'

      def index?
        scoped_read?(RESOURCE) && admin?
      end

      def show?
        scoped_read?(RESOURCE) && (subject.nil? || admin? || own_record?)
      end

      def create?
        scoped_write?(RESOURCE)
      end

      def update?
        scoped_write?(RESOURCE) && own_record?
      end

      def destroy?
        scoped_write?(RESOURCE) && admin? && !own_record?
      end

      def search?
        scoped_read?(RESOURCE) && admin?
      end

      def assign_system_role?
        scoped_write?(RESOURCE) && admin?
      end

      def resend_verification?
        scoped_write?(RESOURCE) && (admin? || own_record?)
      end

      def summary
        super.merge(capabilities: subject_capabilities)
      end

      class Scope < BasePolicy::Scope
        def resolve
          return scope.where(false).order(:id).all unless admin?

          account_id = subject_account_id
          if account_id.nil?
            scope.order(:id).all
          else
            scope.exclude(id: account_id).order(:id).all
          end
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
          can_create_projects: authenticated? && !admin? && email_verified?
        }
      end
    end
  end
end
