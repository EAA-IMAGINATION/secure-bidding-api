# frozen_string_literal: true

require_relative '../lib/demo_seed_crypto'

# rubocop:disable Metrics/AbcSize, Metrics/BlockLength, Metrics/CyclomaticComplexity
# rubocop:disable Metrics/MethodLength, Metrics/PerceivedComplexity
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
    SecureBidding::Services::Roles::EnsureRoles.call

    SecureBidding::Services::Accounts::ResetAccounts.call(
      username: 'scifiengineering',
      password: 'President@1958',
      email: 'scifithedev@gapp.nthu.edu.tw',
      system_role: 'admin'
    )

    account_specs = [
      {
        username: 'scifithedev',
        password: 'President@1958',
        email: 'scifithedev@gmail.com',
        phone: nil,
        system_role: 'member'
      },
      {
        username: 'demo-project-owner',
        password: 'owner-pass-123',
        email: 'owner@secure-bidding.local',
        phone: '+886900100002',
        system_role: 'project_owner'
      },
      {
        username: 'demo-bidder',
        password: 'bidder-pass-123',
        email: 'bidder@secure-bidding.local',
        phone: '+886900100003',
        system_role: 'bidder'
      }
    ]

    created_accounts = account_specs.map do |spec|
      result = SecureBidding::Services::Accounts::CreateAccount.call(spec)
      raise "Account seed failed for #{spec[:username]}: #{result[:error]}" unless result[:ok]

      account = result[:account]
      account.verify_email! if account.email_verified_at.nil?
      account
    end

    owner = created_accounts.find { |account| account.username == 'demo-project-owner' }
    bidder = created_accounts.find { |account| account.username == 'demo-bidder' }

    # Alpha: past deadline, reveal-ready (keys + decryptable bids + integrity snapshot).
    alpha_project, alpha_keypair = upsert_demo_project(
      title: 'seed-project-alpha',
      budget_cents: 120_000,
      crypto_label: 'alpha',
      bidding_deadline: Time.now + 3600
    )
    # Beta: future deadline, sealed bidding demo.
    beta_project, beta_keypair = upsert_demo_project(
      title: 'seed-project-beta',
      budget_cents: 250_000,
      crypto_label: 'beta',
      bidding_deadline: Time.now + (2 * 86_400)
    )

    SecureBidding::Services::Roles::AssignSystemRole.call(account_id: owner.id, role_name: 'project_owner')
    SecureBidding::Services::Roles::AssignSystemRole.call(account_id: bidder.id, role_name: 'bidder')

    [
      [owner, alpha_project, 'project_owner'],
      [bidder, alpha_project, 'bidder'],
      [owner, beta_project, 'project_owner'],
      [bidder, beta_project, 'bidder']
    ].each do |account, project, role_name|
      SecureBidding::Services::Projects::AssignProjectRole.call(
        account_id: account.id,
        project_id: project.id,
        role_name: role_name,
        requested_by_admin: true
      )
    end

    bid_specs = [
      {
        project: alpha_project,
        keypair: alpha_keypair,
        crypto_label: 'alpha',
        bidder_account_id: bidder.id,
        contractor_alias: 'seed-vendor-a'
      },
      {
        project: beta_project,
        keypair: beta_keypair,
        crypto_label: 'beta',
        bidder_account_id: bidder.id,
        contractor_alias: 'seed-vendor-b'
      }
    ]

    bid_specs.each do |bid_spec|
      bid_submission = upsert_demo_bid(
        project: bid_spec[:project],
        bidder_account_id: bid_spec[:bidder_account_id],
        contractor_alias: bid_spec[:contractor_alias],
        private_key: bid_spec[:keypair][:private_key],
        crypto_label: bid_spec[:crypto_label]
      )

      SecureBidding::Services::Payments::CreatePayment.call(
        'bid_submission_id' => bid_submission.id,
        'paid' => false,
        'method' => 'placeholder',
        'reference' => "seed-#{bid_submission.id[0..7]}"
      )
    end

    alpha_project.update(bidding_deadline: Time.now - 3600)
    SecureBidding::Services::Projects::GenerateIntegritySnapshot.call(alpha_project.refresh)
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/BlockLength, Metrics/CyclomaticComplexity
# rubocop:enable Metrics/MethodLength, Metrics/PerceivedComplexity
