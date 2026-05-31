# frozen_string_literal: true

module SecureBidding
  module Policies
    class BidPolicy < BasePolicy
      RESOURCE = 'bids'

      def index?
        scoped_read?(RESOURCE) && admin?
      end

      def show?
        return scoped_read?(RESOURCE) if subject.nil?

        scoped_read?(RESOURCE) && (admin? || linked_project_manage? || legacy_public_bid?)
      end

      def create?
        scoped_write?(RESOURCE) && linked_project_manage?
      end

      class Scope < BasePolicy::Scope
        def resolve
          ids = Bid.all.filter_map do |bid_id|
            bid = Bid.find(bid_id)
            next unless bid

            bid.id
          end

          return ids if admin? || subject.nil?

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

      def linked_project_manage?
        project = Project[record.project_id]
        return false unless project

        ProjectPolicy.new(subject, project, auth_scope: auth_scope).manage?
      end

      def legacy_public_bid?
        Project[record.project_id].nil?
      end
    end
  end
end
