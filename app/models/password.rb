# frozen_string_literal: true

require 'rack/utils'
require_relative '../lib/key_stretching'

module SecureBidding
  # Handles password digest creation and verification.
  class Password
    def self.digest(plaintext)
      salt = KeyStretching.generate_salt
      {
        salt: salt,
        hash: KeyStretching.stretch(plaintext, salt)
      }
    end

    def self.valid?(candidate, salt:, hash:)
      return false if salt.to_s.empty? || hash.to_s.empty?

      candidate_hash = KeyStretching.stretch(candidate, salt)
      Rack::Utils.secure_compare(candidate_hash, hash.to_s)
    end
  end
end
