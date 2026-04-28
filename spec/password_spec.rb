# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require_relative '../app/require_app'

describe 'SecureBidding::Password' do
  it 'creates a salted key-stretched digest that does not expose plaintext' do
    digest = SecureBidding::Password.digest('p@ssw0rd')

    _(digest[:salt]).wont_be_nil
    _(digest[:hash]).wont_be_nil
    _(digest[:hash]).wont_equal 'p@ssw0rd'
  end

  it 'verifies password candidates against an existing digest' do
    digest = SecureBidding::Password.digest('correct-horse-battery-staple')

    _(SecureBidding::Password.valid?('correct-horse-battery-staple', salt: digest[:salt], hash: digest[:hash]))
      .must_equal true
    _(SecureBidding::Password.valid?('wrong-password', salt: digest[:salt], hash: digest[:hash]))
      .must_equal false
  end
end
