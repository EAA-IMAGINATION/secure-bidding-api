# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require_relative '../app/require_app'

describe SecureBidding::AuthScope do
  it 'allows read and write for FULL scope' do
    scope = SecureBidding::AuthScope.new(SecureBidding::AuthScope::FULL)
    _(scope.can_read?('projects')).must_equal true
    _(scope.can_write?('projects')).must_equal true
  end

  it 'allows read but not write for READ_ONLY scope' do
    scope = SecureBidding::AuthScope.new(SecureBidding::AuthScope::READ_ONLY)
    _(scope.can_read?('projects')).must_equal true
    _(scope.can_write?('projects')).must_equal false
  end

  it 'write implies read' do
    scope = SecureBidding::AuthScope.new('projects:write')
    _(scope.can_read?('projects')).must_equal true
    _(scope.can_write?('projects')).must_equal true
  end
end

describe 'SecureBidding::AuthToken scoped tokens' do
  before do
    SecureBidding::AuthToken.setup(SecureBidding::AuthToken.generate_key)
  end

  it 'persists scope through load' do
    payload = { account_id: 'abc', username: 'alice', system_role: 'member' }
    token = SecureBidding::AuthToken.new(payload, SecureBidding::AuthToken::ONE_HOUR,
                                         scope: SecureBidding::AuthScope.new(SecureBidding::AuthScope::READ_ONLY))
    loaded = SecureBidding::AuthToken.load(token.to_s)
    _(loaded.scope.to_s).must_equal SecureBidding::AuthScope::READ_ONLY
  end

  it 'defaults legacy tokens without scope to FULL' do
    legacy = {
      payload: { account_id: 'abc' },
      exp: Time.now.to_i + 3600
    }
    ciphertext = SecureBidding::AuthToken.encrypt(JSON.generate(legacy))
    loaded = SecureBidding::AuthToken.load(ciphertext)
    _(loaded.scope.to_s).must_equal SecureBidding::AuthScope::FULL
  end
end
