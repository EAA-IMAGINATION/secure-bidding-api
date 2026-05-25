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

          contractor_alias = payload['contractor_alias']
          plaintext_bid = payload['plaintext_bid']

          auth_account_id = auth_account[:account_id] || auth_account['account_id']
          if [contractor_alias, plaintext_bid].any? { |value| value.to_s.strip.empty? }
            return { ok: false, status: 400,
                     error: 'contractor_alias and plaintext_bid are required' }
          end

          return { ok: false, status: 403, error: 'Project owner cannot bid on own project' } if owner_of_project?(project.id, auth_account_id)

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
          return false if owner_role.nil?

          SecureBidding::ProjectMembership.first(
            account_id: account_id,
            project_id: project_id,
            role_id: owner_role.id
          ) != nil
        end
      end
    end
  end
end
