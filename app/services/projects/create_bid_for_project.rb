# frozen_string_literal: true

module SecureBidding
  module Services
    module Projects
      # Creates a bid submission for a project if bidder membership is present.
      class CreateBidForProject
        def self.call(project_id:, payload:)
          project = SecureBidding::Project[project_id]
          return { ok: false, status: 404, error: 'Project not found' } if project.nil?

          bidder_account_id = payload['bidder_account_id']
          contractor_alias = payload['contractor_alias']
          plaintext_bid = payload['plaintext_bid']

          if [bidder_account_id, contractor_alias, plaintext_bid].any? { |value| value.to_s.strip.empty? }
            return { ok: false, status: 400,
                     error: 'bidder_account_id, contractor_alias, and plaintext_bid are required' }
          end

          bidder = SecureBidding::Account[bidder_account_id]
          if bidder.nil?
            return { ok: false, status: 400,
                     error: 'bidder_account_id must reference an existing account' }
          end

          bidder_role = SecureBidding::Role.first(name: 'bidder')
          membership = SecureBidding::ProjectMembership.first(
            account_id: bidder.id,
            project_id: project.id,
            role_id: bidder_role.id
          )
          return { ok: false, status: 403, error: 'bidder account is not assigned to this project' } if membership.nil?

          bid_submission = SecureBidding::BidSubmission.new(
            project_id: project.id,
            contractor_alias: contractor_alias
          )
          bid_submission.encrypt_bid(plaintext_bid)
          bid_submission.save
          { ok: true, bid_submission: bid_submission }
        end
      end
    end
  end
end
