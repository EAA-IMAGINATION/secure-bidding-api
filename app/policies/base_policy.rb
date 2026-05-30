# frozen_string_literal: true

module SecureBidding
  module Policies
    class BasePolicy
      attr_reader :subject, :record

      def initialize(subject, record)
        @subject = subject
        @record = record
      end

      def summary
        self.class.public_instance_methods(false)
          .grep(/\?\z/)
          .sort
          .each_with_object({}) do |method_name, result|
            result[method_name.to_s.delete_suffix('?').to_sym] = public_send(method_name)
          end
      end

      class Scope
        attr_reader :subject, :scope

        def initialize(subject, scope)
          @subject = subject
          @scope = scope
        end

        def resolve
          scope
        end

        private

        def subject_account_id
          return nil if subject.nil?

          if subject.respond_to?(:id)
            subject.id
          else
            subject[:account_id] || subject['account_id']
          end
        end

        def subject_system_role
          return nil if subject.nil?

          if subject.respond_to?(:system_role)
            subject.system_role
          else
            subject[:system_role] || subject['system_role']
          end
        end

        def subject_has_system_role?(role_name)
          return false if subject.nil?

          if subject.respond_to?(:system_role?)
            subject.system_role?(role_name)
          else
            subject_system_role == role_name
          end
        end

        def admin?
          subject_has_system_role?('admin') || subject_has_system_role?('system_admin')
        end

        def email_verified?
          return true if admin?
          return false if subject.nil?

          account_id = subject_account_id
          return false if account_id.nil?

          account = SecureBidding::Account[account_id]
          account && !account.email_verified_at.nil?
        end
      end

      private

      def subject_account_id
        return nil if subject.nil?

        if subject.respond_to?(:id)
          subject.id
        else
          subject[:account_id] || subject['account_id']
        end
      end

      def subject_system_role
        return nil if subject.nil?

        if subject.respond_to?(:system_role)
          subject.system_role
        else
          subject[:system_role] || subject['system_role']
        end
      end

      def subject_has_system_role?(role_name)
        return false if subject.nil?

        if subject.respond_to?(:system_role?)
          subject.system_role?(role_name)
        else
          subject_system_role == role_name
        end
      end

      def admin?
        subject_has_system_role?('admin') || subject_has_system_role?('system_admin')
      end

      def authenticated?
        !subject.nil?
      end

      def email_verified?
        return true if admin?
        return false unless authenticated?

        account = subject_account_record
        account && !account.email_verified_at.nil?
      end

      def subject_account_record
        return subject if subject.is_a?(SecureBidding::Account)

        account_id = subject_account_id
        return nil if account_id.nil?

        SecureBidding::Account[account_id]
      end
    end
  end
end
