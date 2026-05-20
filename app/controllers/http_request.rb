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

      @routing.scheme.casecmp('https').zero?
    end

    def body_data
      raw = @routing.body.read
      raw.empty? ? {} : JSON.parse(raw, symbolize_names: true)
    end

    def authenticated_account
      header = @routing.env['HTTP_AUTHORIZATION']
      return nil if header.nil?

      scheme, token = header.split(' ', 2)
      return nil if scheme.nil? || token.nil?
      return nil unless scheme.casecmp('bearer').zero?

      auth_token = AuthToken.load(token)
      auth_token.payload
    end
  end
end
