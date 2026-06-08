# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'base64'
require 'json'
require 'minitest/autorun'
require 'rack/test'
require_relative '../app/require_app'

module SignedRequestHelpers
  def signed_json(data)
    SecureBidding::SignedRequest.sign(data).to_json
  end

  def signed_post(path, data, headers = {})
    post path, signed_json(data), { 'CONTENT_TYPE' => 'application/json' }.merge(headers)
  end
end

module ClientCiphertextHelpers
  def sample_client_envelope(label = 'secret')
    {
      ephemeralPublicKey: Base64.strict_encode64('e' * 32),
      nonce: Base64.strict_encode64('n' * 24),
      ciphertext: Base64.strict_encode64(label)
    }
  end

  def sample_client_bid_payload(label = 'secret')
    envelope = sample_client_envelope(label)
    {
      encrypted_bid_amount: envelope,
      encrypted_proposal_text: sample_client_envelope("#{label}-proposal")
    }
  end
end

Minitest::Spec.include SignedRequestHelpers
Minitest::Spec.include ClientCiphertextHelpers
