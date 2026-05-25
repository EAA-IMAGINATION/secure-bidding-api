# frozen_string_literal: true

module SecureBidding
  module Services
    module Projects
      # Creates a bid submission for a project if bidder membership is present.
      class CreateBidForProject
        def self.call(project_id:, payload:, auth_account:)
          project = SecureBidding::Project[project_id]
          return { ok: false, status: 404, error: 'Project not found' } if project.nil?
          return { ok: false, status: 403, error: 'Project is not open for bidding' } unless project.state == 'published'
          return { ok: false, status: 403, error: 'Login required to bid on projects' } if auth_account.nil?

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

          auth_account_id = auth_account[:account_id] || auth_account['account_id']
          return { ok: false, status: 403, error: 'Not authorized to bid for this account' } if auth_account_id != bidder.id
          return { ok: false, status: 403, error: 'Project owner cannot bid on own project' } if owner_of_project?(project.id, bidder.id)

          bid_submission = SecureBidding::BidSubmission.new(
            project_id: project.id,
            contractor_alias: contractor_alias
          )
          bid_submission.encrypt_bid(plaintext_bid)
          bid_submission.save
          { ok: true, bid_submission: bid_submission }
        end

        def self.owner_of_project?(project_id, account_id)
          owner_role = SecureBidding::Role.first(name: 'project_owner')
          if owner_role
            owner_membership = SecureBidding::ProjectMembership.first(
              account_id: account_id,
              project_id: project_id,
              role_id: owner_role.id
            )
            return true unless owner_membership.nil?
          end

          collaboration = SecureBidding::AccountProject.first(
            account_id: account_id,
            project_id: project_id
          )
          !collaboration.nil? && collaboration.collaboration_role == 'owner'
        end
      end
    end
  end
end
