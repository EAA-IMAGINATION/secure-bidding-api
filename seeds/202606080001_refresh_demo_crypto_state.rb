# frozen_string_literal: true

require_relative '../lib/demo_seed_crypto'

# rubocop:disable Metrics/AbcSize, Metrics/BlockLength, Metrics/MethodLength
Sequel.seed(:development) do
  def upsert_demo_project(title:, budget_cents:, crypto_label:, bidding_deadline:)
    keypair = SecureBidding::DemoSeedCrypto.keypair_for(crypto_label)
    wrapped = SecureBidding::DemoSeedCrypto.wrap_private_key(keypair[:secret_bytes], crypto_label)
    attrs = {
      title: title,
      budget_cents: budget_cents,
      state: 'published',
      nacl_public_key: keypair[:public_key_b64],
      nacl_encrypted_private_key: wrapped,
      bidding_deadline: bidding_deadline
    }
    project = SecureBidding::Project.first(title: title)
    project ? project.update(attrs) : SecureBidding::Project.create(attrs)
    project = SecureBidding::Project.first(title: title)
    [project, keypair]
  end

  def upsert_demo_bid(project:, bidder_account_id:, contractor_alias:, private_key:, crypto_label:)
    amount = SecureBidding::DemoSeedCrypto.encrypt_for_project(
      private_key, project.budget_cents - 10_000, "#{crypto_label}-amount"
    )
    proposal = SecureBidding::DemoSeedCrypto.encrypt_for_project(
      private_key, "Sealed demo proposal for #{project.title}.", "#{crypto_label}-proposal"
    )
    existing = SecureBidding::BidSubmission.first(
      project_id: project.id,
      contractor_alias: contractor_alias
    )
    if existing
      existing.update(encrypted_bid_amount: amount, encrypted_proposal_text: proposal)
      return existing
    end

    result = SecureBidding::Services::Projects::CreateBidForProject.call(
      project_id: project.id,
      payload: {
        'bidder_account_id' => bidder_account_id,
        'contractor_alias' => contractor_alias,
        'encrypted_bid_amount' => amount,
        'encrypted_proposal_text' => proposal
      },
      auth_account: { account_id: bidder_account_id }
    )
    raise "Bid seed failed for #{contractor_alias}: #{result[:error]}" unless result[:ok]

    result[:bid_submission]
  end

  def run
    bidder = SecureBidding::Account.first(username: 'demo-bidder')
    return if bidder.nil?

    alpha_project, alpha_keypair = upsert_demo_project(
      title: 'seed-project-alpha',
      budget_cents: 120_000,
      crypto_label: 'alpha',
      bidding_deadline: Time.now + 3600
    )
    beta_project, beta_keypair = upsert_demo_project(
      title: 'seed-project-beta',
      budget_cents: 250_000,
      crypto_label: 'beta',
      bidding_deadline: Time.now + (2 * 86_400)
    )

    upsert_demo_bid(
      project: alpha_project,
      bidder_account_id: bidder.id,
      contractor_alias: 'seed-vendor-a',
      private_key: alpha_keypair[:private_key],
      crypto_label: 'alpha'
    )
    upsert_demo_bid(
      project: beta_project,
      bidder_account_id: bidder.id,
      contractor_alias: 'seed-vendor-b',
      private_key: beta_keypair[:private_key],
      crypto_label: 'beta'
    )

    alpha_project.update(bidding_deadline: Time.now - 3600)
    SecureBidding::Services::Projects::GenerateIntegritySnapshot.call(alpha_project.refresh)
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/BlockLength, Metrics/MethodLength
