# frozen_string_literal: true

require 'base64'

require_relative 'base_form'

module SecureBidding
  module Forms
    class BidsCreateForm < BaseForm
      UUID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i.freeze
      MAX_CONTRACTOR_LENGTH = 200
      MAX_ENCRYPTED_BID_LENGTH = 65_536

      params do
        required(:contractor).filled(:string)
        required(:project_id).filled(:string)
        required(:encrypted_bid).filled(:string)
      end

      rule(:contractor) do
        trimmed = value.to_s.strip
        key.failure('contractor is required and cannot be empty') if trimmed.empty?
        key.failure("contractor must be at most #{MAX_CONTRACTOR_LENGTH} characters") if trimmed.length > MAX_CONTRACTOR_LENGTH
      end

      rule(:project_id) do
        key.failure('project_id must be a UUID') unless value.to_s.match?(UUID_FORMAT)
      end

      rule(:encrypted_bid) do
        trimmed = value.to_s.strip
        key.failure('encrypted_bid is required and cannot be empty') if trimmed.empty?
        if trimmed.length > MAX_ENCRYPTED_BID_LENGTH
          key.failure("encrypted_bid must be at most #{MAX_ENCRYPTED_BID_LENGTH} characters")
        end

        Base64.strict_decode64(trimmed)
      rescue ArgumentError
        key.failure('encrypted_bid must be valid base64')
      end
    end
  end
end
