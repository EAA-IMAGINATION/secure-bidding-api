# frozen_string_literal: true

require_relative 'oidc_verifier'

module SecureBidding
  class GoogleIdToken
    JWKS_URI = 'https://www.googleapis.com/oauth2/v3/certs'
    ISSUERS = ['https://accounts.google.com', 'accounts.google.com'].freeze

    def self.verify(id_token)
      verifier.verify(id_token)
    end

    def self.verifier
      @verifier ||= OidcVerifier.new(
        jwks_uri: ENV.fetch('GOOGLE_JWKS_URL', JWKS_URI),
        audience: ENV.fetch('GOOGLE_CLIENT_ID'),
        allowed_issuers: ISSUERS
      )
    end
  end
end
