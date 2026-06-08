# frozen_string_literal: true

module SecureBidding
  module Services
    module Projects
      class AwardBid
        def self.call(project_id:, bid_submission_id:, auth_account:, awarded_bid_amount_cents: nil)
          project = SecureBidding::Project[project_id]
          return { ok: false, status: 404, error: 'Project not found' } if project.nil?

          policy = SecureBidding::Policies::ProjectPolicy.new(auth_account, project)
          return { ok: false, status: 403, error: 'Not authorized to award bids' } unless policy.award_bid?

          bid = SecureBidding::BidSubmission[bid_submission_id]
          return { ok: false, status: 404, error: 'Bid not found' } if bid.nil? || bid.project_id != project.id

          amount = awarded_bid_amount_cents.to_s.strip
          return { ok: false, status: 400, error: 'awarded_bid_amount_cents is required' } if amount.empty?
          return { ok: false, status: 400, error: 'awarded_bid_amount_cents must be a non-negative integer' } unless amount.match?(/\A\d+\z/)

          project.update(
            state: 'in_progress',
            awarded_bid_submission_id: bid.id,
            awarded_bid_amount_cents: amount.to_i,
            payment_status: 'none',
            payment_amount_cents: nil
          )
          { ok: true, project: project, awarded_bid_submission_id: bid.id }
        end
      end
    end
  end
end
