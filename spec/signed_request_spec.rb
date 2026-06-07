# frozen_string_literal: true

require_relative 'spec_helper'

describe 'SecureBidding::SignedRequest' do
  let(:keypair) { SecureBidding::SignedRequest.generate_keypair }
  let(:payload) { { username: 'alice', password: 'secret123' } }

  before do
    @config_keys = %i[@verify_key @signing_key].map do |var|
      SecureBidding::SignedRequest.instance_variable_get(var)
    end
  end

  after do
    SecureBidding::SignedRequest.instance_variable_set(:@verify_key, @config_keys[0])
    SecureBidding::SignedRequest.instance_variable_set(:@signing_key, @config_keys[1])
  end

  it 'generates Base64-encoded 32-byte keys' do
    _(Base64.strict_decode64(keypair[:signing_key]).bytesize).must_equal 32
    _(Base64.strict_decode64(keypair[:verify_key]).bytesize).must_equal 32
  end

  it 'round-trips a signed message via sign then parse' do
    SecureBidding::SignedRequest.setup(keypair[:verify_key], keypair[:signing_key])

    signed = SecureBidding::SignedRequest.sign(payload)
    _(SecureBidding::SignedRequest.parse(signed)).must_equal payload
  end

  it 'raises VerificationError on a forged signature' do
    SecureBidding::SignedRequest.setup(keypair[:verify_key], keypair[:signing_key])
    signed = SecureBidding::SignedRequest.sign(payload)

    forger = SecureBidding::SignedRequest.generate_keypair
    forged_signature = Base64.strict_encode64(
      RbNaCl::SigningKey.new(Base64.strict_decode64(forger[:signing_key]))
        .sign(payload.to_json)
    )

    _ { SecureBidding::SignedRequest.parse(data: payload, signature: forged_signature) }
      .must_raise SecureBidding::SignedRequest::VerificationError
  end

  it 'raises KeypairError when setup runs verify-only and sign is called' do
    SecureBidding::SignedRequest.setup(keypair[:verify_key])

    _ { SecureBidding::SignedRequest.sign(payload) }
      .must_raise SecureBidding::SignedRequest::KeypairError
  end
end
