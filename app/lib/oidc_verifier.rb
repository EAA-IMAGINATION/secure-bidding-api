# frozen_string_literal: true

require 'jwt'
require 'json'
require 'http'

module SecureBidding
  class OidcVerifier
    class VerificationError < StandardError; end

    def initialize(jwks_uri:, audience:, allowed_issuers:)
      @jwks_uri = jwks_uri
      @audience = audience
      @allowed_issuers = Array(allowed_issuers)
      @keys_by_kid = {}
    end

    def verify(id_token)
      raise VerificationError, 'Missing id_token' if id_token.to_s.empty?

      claims, = JWT.decode(
        id_token, signing_key(key_id(id_token)), true,
        algorithms: ['RS256'], verify_expiration: true
      )
      validate_claims!(claims)
      claims
    rescue JWT::DecodeError => e
      raise VerificationError, "Invalid id_token: #{e.message}"
    end

    private

    def key_id(id_token)
      _, header = JWT.decode(id_token, nil, false)
      header['kid'] or raise VerificationError, 'id_token header has no kid'
    end

    def signing_key(kid)
      @keys_by_kid[kid] || refresh_keys[kid] ||
        raise(VerificationError, "No JWKS key for kid #{kid}")
    end

    def refresh_keys
      response = HTTP.get(@jwks_uri)
      raise VerificationError, 'Could not fetch JWKS' unless response.status.success?

      keys = JSON.parse(response.to_s).fetch('keys')
      @keys_by_kid = keys.to_h { |jwk| [jwk['kid'], JWT::JWK.import(jwk).verify_key] }
    end

    def validate_claims!(claims)
      raise VerificationError, "Untrusted issuer: #{claims['iss']}" \
        unless @allowed_issuers.include?(claims['iss'])
      raise VerificationError, 'Audience mismatch' unless claims['aud'] == @audience
    end
  end
end
