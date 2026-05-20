# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require_relative '../app/require_app'

# rubocop:disable Metrics/BlockLength
describe 'SecureBidding::Account' do
  before do
    SecureBidding::Database.migrate!
    SecureBidding::BidSubmission.dataset.delete
    SecureBidding::Project.dataset.delete
    SecureBidding::AccountProject.dataset.delete
    SecureBidding::Account.dataset.delete
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
