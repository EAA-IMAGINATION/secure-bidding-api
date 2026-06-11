# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require_relative '../app/require_app'

describe 'EnsurePlatformAdmin service' do
  before do
    SecureBidding::Database.migrate!
    SecureBidding::AccountRole.dataset.delete
    SecureBidding::Account.dataset.delete
    SecureBidding::Services::Roles::EnsureRoles.call
  end

  it 'promotes scifiengineering and demotes scifithedev without deleting projects' do
    project = SecureBidding::Project.create(title: 'keep-me', budget_cents: 10_000)

    scifi = SecureBidding::Services::Accounts::CreateAccount.call(
      username: 'scifiengineering',
      password: 'admin-pass-123',
      email: 'scifithedev@gapp.nthu.edu.tw',
      system_role: 'member'
    )[:account]
    scifi.verify_email!

    scifi_dev = SecureBidding::Services::Accounts::CreateAccount.call(
      username: 'scifithedev',
      password: 'member-pass-123',
      email: 'scifithedev@gmail.com',
      system_role: 'admin'
    )[:account]
    scifi_dev.verify_email!

    SecureBidding::Services::Projects::AssignProjectRole.call(
      account_id: scifi_dev.id,
      project_id: project.id,
      role_name: 'project_owner',
      requested_by_admin: true
    )

    result = SecureBidding::Services::Accounts::EnsurePlatformAdmin.call(platform_admin_username: 'scifiengineering')

    _(result[:ok]).must_equal true
    _(SecureBidding::Account[scifi.id].system_role).must_equal 'admin'
    _(SecureBidding::Account[scifi_dev.id].system_role).must_equal 'member'
    _(SecureBidding::Project[project.id]).wont_be_nil
    _(SecureBidding::ProjectMembership.where(account_id: scifi_dev.id, project_id: project.id).count).must_equal 1
  end
end
