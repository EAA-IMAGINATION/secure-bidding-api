# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

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

Minitest::Spec.include SignedRequestHelpers
