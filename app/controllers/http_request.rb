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
  end
end
