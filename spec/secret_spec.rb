# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require_relative '../app/require_app'

describe 'SecureBidding::Secret' do
  before do
    SecureBidding::Database.migrate!
    SecureBidding::Secret.dataset.delete
    SecureBidding::Account.dataset.delete
  end

  it 'encrypts plaintext and decrypts it back with the same key' do
    account = SecureBidding::Account.create(username: 'alice', email: 'alice@example.com')
    secret = SecureBidding::Secret.new(account_id: account.id, title: 'credentials')

    secret.encrypt_data('my-plaintext-password')
    secret.save

    stored = SecureBidding::Secret.first
    _(stored.secure_encrypted_data).wont_equal 'my-plaintext-password'
    _(stored.decrypt_data).must_equal 'my-plaintext-password'
  end

  it 'belongs to account and account has many secrets' do
    account = SecureBidding::Account.create(username: 'bob', email: 'bob@example.com')
    secret = SecureBidding::Secret.new(account_id: account.id, title: 'token')
    secret.encrypt_data('ciphertext')
    secret.save

    _(secret.account.id).must_equal account.id
    _(account.secrets.map(&:id)).must_include secret.id
  end
end
