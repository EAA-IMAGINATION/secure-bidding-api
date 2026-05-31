# frozen_string_literal: true

module SecureBidding
  module Policies
    class BidPolicy < BasePolicy
      RESOURCE = 'bids'

      def index?
        authenticated? && scoped_read?(RESOURCE) && (admin? || manages_any_project?)
      end

      def show?
        return false unless authenticated? && scoped_read?(RESOURCE)

        admin? || linked_project_manage?
      end

      def create?
        authenticated? && scoped_write?(RESOURCE) && linked_project_manage?
      end

      class Scope < BasePolicy::Scope
        def resolve
          return [] unless subject

          ids = Bid.all.filter_map do |bid_id|
            bid = Bid.find(bid_id)
            next unless bid

            bid.id
          end

          return ids if admin?

          account_id = subject_account_id
          return [] if account_id.nil?

          managed_ids = ProjectPolicy.managed_project_ids_for(account_id)
          ids.select do |bid_id|
            bid = Bid.find(bid_id)
            bid && managed_ids.include?(bid.project_id)
          end
        end
      end

      private

      def manages_any_project?
        account_id = subject_account_id
        return false if account_id.nil?

        ProjectPolicy.managed_project_ids_for(account_id).any?
      end

      def linked_project_manage?
        project = Project[record.project_id]
        return false unless project

        ProjectPolicy.new(subject, project, auth_scope: auth_scope).manage?
      end
    end
  end
end
