# frozen_string_literal: true

require 'json'
require_relative 'secure_messaging'

module SecureBidding
  # Encrypts and decrypts pending registration payloads.
  class RegistrationToken
    class InvalidTokenError < StandardError; end

    def initialize(messenger = SecureMessaging.new)
      @messenger = messenger
    end

    def generate(username:, email:)
      @messenger.encrypt({ 'username' => username, 'email' => email }.to_json)
    end

    def decode(token)
      JSON.parse(@messenger.decrypt(token))
    rescue StandardError => e
      raise InvalidTokenError, e.message
    end
  end
end
