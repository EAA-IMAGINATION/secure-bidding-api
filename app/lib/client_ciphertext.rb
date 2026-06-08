# frozen_string_literal: true

require 'json'

module SecureBidding
  # Validates and normalizes NaCl box envelopes posted from the web app.
  module ClientCiphertext
    REQUIRED_KEYS = %w[ephemeralPublicKey nonce ciphertext].freeze

    module_function

    def valid_envelope?(value)
      envelope = parse_envelope(value)
      return false if envelope.nil?

      REQUIRED_KEYS.all? { |key| envelope[key].to_s.strip != '' }
    end

    def normalize_envelope(value)
      envelope = parse_envelope(value)
      raise ArgumentError, 'invalid client ciphertext envelope' if envelope.nil?

      missing = REQUIRED_KEYS.reject { |key| envelope[key].to_s.strip != '' }
      raise ArgumentError, "client ciphertext missing #{missing.join(', ')}" unless missing.empty?

      envelope.to_json
    end

    def parse_envelope(value)
      return value.transform_keys(&:to_s) if value.is_a?(Hash)

      JSON.parse(value.to_s)
    rescue JSON::ParserError
      nil
    end
  end
end
