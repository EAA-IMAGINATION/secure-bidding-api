# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require_relative '../app/require_app'

# rubocop:disable Metrics/BlockLength
describe 'SecureBidding::Services::Accounts::ResetAccounts' do
  before do
    SecureBidding::Database.migrate!
    SecureBidding::BidSubmission.dataset.delete
    SecureBidding::ProjectMembership.dataset.delete
    SecureBidding::AccountRole.dataset.delete
    SecureBidding::AccountProject.dataset.delete
    SecureBidding::Project.dataset.delete
    SecureBidding::Account.dataset.delete
  end

  it 'replaces the account set with the requested admin bootstrap account' do
    project = SecureBidding::Project.create(title: 'legacy-project', budget_cents: 50_000)
    legacy_account = SecureBidding::Services::Accounts::CreateAccount.call(
      username: 'legacy-user',
      password: 'legacy-pass-123',
      email: 'legacy@example.com',
      system_role: 'member'
    )[:account]
    SecureBidding::Services::Roles::EnsureRoles.call
    SecureBidding::Services::Roles::AssignSystemRole.call(
      account_id: legacy_account.id,
      role_name: 'system_admin'
    )
    legacy_account.add_collaboration(project, collaboration_role: 'owner')
    SecureBidding::Services::Projects::AssignProjectRole.call(
      account_id: legacy_account.id,
      project_id: project.id,
      role_name: 'project_owner',
      requested_by_admin: true
    )

    result = SecureBidding::Services::Accounts::ResetAccounts.call(
      username: 'scifithedev',
      password: 'President@1958',
      email: 'scifithedev@gmail.com',
      system_role: 'admin'
    )

    _(result[:ok]).must_equal true
    _(SecureBidding::Account.count).must_equal 1
    _(SecureBidding::AccountRole.count).must_equal 0
    _(SecureBidding::AccountProject.count).must_equal 0
    _(SecureBidding::ProjectMembership.count).must_equal 0

    bootstrap = SecureBidding::Account.first(username: 'scifithedev')
    _(bootstrap).wont_be_nil
    _(bootstrap.system_role).must_equal 'admin'
    _(bootstrap.email).must_equal 'scifithedev@gmail.com'
    _(bootstrap.check_password('President@1958')).must_equal true
  end
end
# rubocop:enable Metrics/BlockLength
