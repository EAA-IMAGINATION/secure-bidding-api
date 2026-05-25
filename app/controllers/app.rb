# frozen_string_literal: true

require 'roda'
require 'json'
require 'logger'
require_relative '../models/bid'
require_relative '../models/project'
require_relative '../models/bid_submission'
require_relative '../models/account'
require_relative '../models/project_membership'
require_relative '../models/payment'
require_relative '../services/accounts/create_account'
require_relative '../services/accounts/get_account'
require_relative '../services/accounts/search_accounts'
require_relative '../services/accounts/update_account'
require_relative '../services/roles/ensure_roles'
require_relative '../services/roles/assign_system_role'
require_relative '../services/projects/create_project_requirement'
require_relative '../services/projects/assign_project_role'
require_relative '../services/projects/create_bid_for_project'
require_relative '../services/payments/create_payment'
require_relative '../services/payments/update_payment'
require_relative '../services/authenticate_account'
require_relative 'http_request'
require_relative 'routes/auth'
require_relative 'routes/bids'
require_relative 'routes/projects'
require_relative 'routes/accounts'
require_relative 'routes/payments'
require_relative 'routes/bid_submissions'

module SecureBidding
  # Rack application for the secure bidding API.
  class App < Roda
    UUID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/.freeze
    APP_LOGGER = Logger.new($stdout)

    plugin :json
    plugin :halt
    plugin :all_verbs
    plugin :multi_route
    plugin :environments
    plugin :error_handler do |error|
      APP_LOGGER.error("Unhandled error: #{error.class} - #{error.message}")
      raise error
    end

    configure :production do
      plugin :redirect_http_to_https
      plugin :hsts
    end

    def parse_json_request_body
      JSON.parse(request.body.read)
    rescue JSON::ParserError
      response.status = 400
      { error: 'Invalid JSON payload' }
    end

    def valid_uuid?(value)
      value.to_s.match?(UUID_FORMAT)
    end

    def log_mass_assignment_attempt(resource, payload, allowed_columns)
      payload_keys = payload.keys.map(&:to_s)
      blocked_keys = payload_keys - allowed_columns.map(&:to_s)
      APP_LOGGER.warn("[mass_assignment] resource=#{resource} keys=#{blocked_keys.join(',')}")
    end

    def account_response(account)
      {
        id: account.id,
        username: account.username,
        system_role: account.system_role,
        email: account.email,
        phone: account.phone
      }
    end

    def project_membership_response(membership)
      {
        id: membership.id,
        project_id: membership.project_id,
        account_id: membership.account_id,
        role: membership.role.name
      }
    end

    def payment_response(payment)
      {
        id: payment.id,
        bid_submission_id: payment.bid_submission_id,
        paid: payment.paid,
        method: payment[:method],
        reference: payment.reference,
        paid_at: payment.paid_at
      }
    end

    def auth_account
      @auth_account
    end

    # rubocop:disable Metrics/BlockLength
    route do |r|
      # CORS headers for cross-origin requests
      r.response.headers["Access-Control-Allow-Origin"] = ENV.fetch("CORS_ORIGIN", "*")
      r.response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, PATCH, OPTIONS"
      r.response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
      r.response.headers["Access-Control-Allow-Credentials"] = "true"

      # Handle preflight requests
      if r.request_method == "OPTIONS"
        return r.response.write ""
      end

      # SSL/TLS enforcement
      unless HttpRequest.new(r).secure?
        r.halt(403, { message: 'TLS/SSL Required' }.to_json)
      end

      # Authentication middleware - extract and validate Bearer token
      http_request = HttpRequest.new(r)
      begin
        @auth_account = http_request.authenticated_account
      rescue InvalidTokenError
        r.halt(403, { message: 'Invalid auth token' }.to_json)
      rescue ExpiredTokenError
        r.halt(403, { message: 'Expired auth token' }.to_json)
      end

      # Root route - health check
      r.root do
        { message: 'Secure Bidding API v1.0', status: 'ok' }
      end

      r.on 'api' do
        r.on 'v1' do
          SecureBidding::Services::Roles::EnsureRoles.call

          SecureBidding::Routes::Auth.call(r, self)

          SecureBidding::Routes::Bids.call(r, self)

          SecureBidding::Routes::Projects.call(r, self)

          SecureBidding::Routes::Accounts.call(r, self)

          SecureBidding::Routes::Payments.call(r, self)

          SecureBidding::Routes::BidSubmissions.call(r, self)

        end
      end
    end

    # rubocop:enable Metrics/BlockLength
  end
end
