# frozen_string_literal: true

module SecureBidding
  # HTTP Request helper methods for validation and security checks
  class HttpRequest
    def initialize(roda_routing)
      @routing = roda_routing
    end

    def secure?
      # Check if request scheme is HTTPS/secure
      # In production, enforce HTTPS; in development/test allow HTTP
      return true if ['test', 'development'].include?(ENV['RACK_ENV'])

      # Heroku and other proxies set X-Forwarded-Proto. Trust it when present.
      forwarded_proto = @routing.env['HTTP_X_FORWARDED_PROTO'] || @routing.env['X-Forwarded-Proto'] || @routing.env['rack.url_scheme']
      if forwarded_proto && !forwarded_proto.to_s.empty?
        # X-Forwarded-Proto may contain a comma-separated list; check the first value
        proto = forwarded_proto.to_s.split(',').first.strip
        return true if proto.casecmp('https').zero?
      end

      @routing.scheme.casecmp('https').zero?
    end

    def body_data
      raw = @routing.body.read
      raw.empty? ? {} : JSON.parse(raw, symbolize_names: true)
    end

    def signed_body_data
      SignedRequest.parse(body_data)
    end

    def authenticated_account
      header = @routing.env['HTTP_AUTHORIZATION']
      return nil if header.nil?

      scheme, token = header.split(' ', 2)
      return nil if scheme.nil? || token.nil?
      return nil unless scheme.casecmp('bearer').zero?

      auth_token = AuthToken.load(token)
      AuthorizedAccount.new(auth_token.payload, auth_token.scope)
    end
  end
end
