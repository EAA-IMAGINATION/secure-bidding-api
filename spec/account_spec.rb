# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'base64'
require 'minitest/autorun'
require_relative '../app/require_app'

# rubocop:disable Metrics/BlockLength
describe 'SecureBidding::Account' do
  before do
    SecureBidding::Database.migrate!
    SecureBidding::Services::Roles::EnsureRoles.call
    SecureBidding::BidSubmission.dataset.delete
    SecureBidding::Project.dataset.delete
    SecureBidding::ProjectMembership.dataset.delete
    SecureBidding::AccountProject.dataset.delete
    SecureBidding::AccountRole.dataset.delete
    SecureBidding::Account.dataset.delete
  end

  def create_member(username:)
    account = SecureBidding::Account.new(username: username, system_role: 'member')
    account.set_password('my-secret-pass')
    account.set_email("#{username}@example.com")
    account.verify_email!
    account.save
    account
  end

  it 'sets and verifies password without exposing plaintext password' do
    account = SecureBidding::Account.new(username: 'alice', system_role: 'member')
    account.set_password('my-secret-pass')
    account.set_email('alice@example.com')
    account.save

    stored = SecureBidding::Account[account.id]
    _(stored.password_hash).wont_equal 'my-secret-pass'
    _(stored.check_password('my-secret-pass')).must_equal true
    _(stored.check_password('wrong-pass')).must_equal false
  end

  it 'stores email and phone as encrypted data plus searchable hashes' do
    account = SecureBidding::Account.new(username: 'bob', system_role: 'member')
    account.set_password('my-secret-pass')
    account.set_email('bob@example.com')
    account.set_phone('+886900123456')
    account.save

    stored = SecureBidding::Account[account.id]
    _(stored.email_secure).wont_equal 'bob@example.com'
    _(stored.phone_secure).wont_equal '+886900123456'
    _(stored.email_hash).must_equal SecureBidding::Account.search_hash('bob@example.com')
    _(stored.phone_hash).must_equal SecureBidding::Account.search_hash('+886900123456')
    _(stored.email).must_equal 'bob@example.com'
    _(stored.phone).must_equal '+886900123456'
  end

  it 'supports many-to-many collaboration links with projects' do
    account = SecureBidding::Account.new(username: 'carol', system_role: 'admin')
    account.set_password('my-secret-pass')
    account.set_email('carol@example.com')
    account.save
    project = SecureBidding::Project.create(title: 'collab-project', budget_cents: 200_000)

    account.add_collaboration(project, collaboration_role: 'owner')

    stored_account = SecureBidding::Account[account.id]
    _(stored_account.collaborations.map(&:id)).must_include project.id
    _(project.refresh.collaborators.map(&:id)).must_include account.id
  end

  it 'includes account and capability roles in profile_roles' do
    account = SecureBidding::Account.new(username: 'admin-user', system_role: 'admin')
    account.set_password('my-secret-pass')
    account.set_email('admin-user@example.com')
    account.save
    SecureBidding::Services::Roles::AssignSystemRole.call(account_id: account.id, role_name: 'system_admin')

    _(account.refresh.profile_roles).must_equal %w[admin system_admin]
  end

  it 'adds project_owner when the account owns a project' do
    owner = create_member(username: 'owner-user')
    project = SecureBidding::Project.create(title: 'owned-project', budget_cents: 100_000, state: 'published')
    owner_role = SecureBidding::Role.ensure_role('project_owner')
    SecureBidding::ProjectMembership.create(account_id: owner.id, project_id: project.id, role_id: owner_role.id)
    SecureBidding::AccountProject.create(account_id: owner.id, project_id: project.id, collaboration_role: 'owner')

    _(owner.refresh.profile_roles).must_equal %w[member project_owner]
  end

  def sample_client_envelope(label = 'secret')
    {
      ephemeralPublicKey: Base64.strict_encode64('e' * 32),
      nonce: Base64.strict_encode64('n' * 24),
      ciphertext: Base64.strict_encode64(label)
    }
  end

  def create_bid(project:, bidder:, contractor_alias: 'alias')
    bid = SecureBidding::BidSubmission.new(
      project_id: project.id,
      contractor_alias: contractor_alias,
      bidder_account_id: bidder.id
    )
    bid.store_client_ciphertext(sample_client_envelope('amount'), sample_client_envelope('proposal'))
    bid.save
    bid
  end

  it 'adds bidder when the account has submitted a bid' do
    create_member(username: 'project-owner')
    bidder = create_member(username: 'bidder-user')
    project = SecureBidding::Project.create(title: 'bid-project', budget_cents: 100_000, state: 'published')
    create_bid(project: project, bidder: bidder)

    _(bidder.refresh.profile_roles).must_equal %w[member bidder]
  end

  it 'adds freelancer when the account is the awarded bidder' do
    create_member(username: 'award-owner')
    freelancer = create_member(username: 'freelancer-user')
    project = SecureBidding::Project.create(title: 'award-project', budget_cents: 100_000, state: 'in_progress')
    bid = create_bid(project: project, bidder: freelancer)
    project.update(awarded_bid_submission_id: bid.id)

    _(freelancer.refresh.profile_roles).must_equal %w[member bidder freelancer]
  end

  it 'removes collaboration join rows when account is deleted' do
    account = SecureBidding::Account.new(username: 'dan', system_role: 'member')
    account.set_password('my-secret-pass')
    account.set_email('dan@example.com')
    account.save
    project = SecureBidding::Project.create(title: 'dependency-project', budget_cents: 100_000)
    account.add_collaboration(project, collaboration_role: 'reviewer')

    _(SecureBidding::AccountProject.count).must_equal 1
    account.destroy
    _(SecureBidding::AccountProject.count).must_equal 0
  end
end
# rubocop:enable Metrics/BlockLength
