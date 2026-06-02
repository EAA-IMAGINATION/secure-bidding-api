# frozen_string_literal: true

# rubocop:disable Metrics/AbcSize, Metrics/BlockLength, Metrics/CyclomaticComplexity
# rubocop:disable Metrics/MethodLength, Metrics/PerceivedComplexity
Sequel.seed(:development) do
  def run
    SecureBidding::Services::Roles::EnsureRoles.call

    SecureBidding::Services::Accounts::ResetAccounts.call(
      username: 'scifithedev',
      password: 'President@1958',
      email: 'scifithedev@gmail.com',
      system_role: 'admin'
    )

    account_specs = [
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

    projects = [
      { title: 'seed-project-alpha', budget_cents: 120_000, state: 'published' },
      { title: 'seed-project-beta', budget_cents: 250_000, state: 'published' }
    ].map do |project_spec|
      SecureBidding::Project.first(title: project_spec[:title]) ||
        SecureBidding::Project.create(project_spec)
    end

    owner = created_accounts.find { |account| account.username == 'demo-project-owner' }
    bidder = created_accounts.find { |account| account.username == 'demo-bidder' }
    alpha_project = projects.find { |project| project.title == 'seed-project-alpha' }
    beta_project = projects.find { |project| project.title == 'seed-project-beta' }

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
        bidder_account_id: bidder.id,
        contractor_alias: 'seed-vendor-a',
        plaintext_bid: 'alpha-secret'
      },
      {
        project: beta_project,
        bidder_account_id: bidder.id,
        contractor_alias: 'seed-vendor-b',
        plaintext_bid: 'beta-secret'
      }
    ]

    bid_specs.each do |bid_spec|
      existing = SecureBidding::BidSubmission.first(
        project_id: bid_spec[:project].id,
        contractor_alias: bid_spec[:contractor_alias]
      )
      bid_submission = existing
      if bid_submission.nil?
        result = SecureBidding::Services::Projects::CreateBidForProject.call(
          project_id: bid_spec[:project].id,
          payload: {
            'bidder_account_id' => bid_spec[:bidder_account_id],
            'contractor_alias' => bid_spec[:contractor_alias],
            'plaintext_bid' => bid_spec[:plaintext_bid]
          },
          auth_account: { account_id: bid_spec[:bidder_account_id] }
        )
        raise "Bid seed failed for #{bid_spec[:contractor_alias]}: #{result[:error]}" unless result[:ok]

        bid_submission = result[:bid_submission]
      end

      SecureBidding::Services::Payments::CreatePayment.call(
        'bid_submission_id' => bid_submission.id,
        'paid' => false,
        'method' => 'placeholder',
        'reference' => "seed-#{bid_submission.id[0..7]}"
      )
    end
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/BlockLength, Metrics/CyclomaticComplexity
# rubocop:enable Metrics/MethodLength, Metrics/PerceivedComplexity
