# frozen_string_literal: true

module SecureBidding
  class GoogleAccount
    def initialize(claims)
      @claims = claims
    end

    def provider = 'google'
    def external_id = @claims['sub']
    def email = @claims['email']
    def name = @claims['name']
    def avatar = @claims['picture']

    def email_verified?
      [true, 'true'].include?(@claims['email_verified'])
    end

    def to_h
      { provider:, external_id:, email:, email_verified: email_verified?, name:, avatar: }
    end
  end
end
