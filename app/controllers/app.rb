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

    def account_response(account, policy: nil)
      payload = {
        id: account.id,
        username: account.username,
        system_role: account.system_role,
        email: account.email,
        phone: account.phone,
        email_verified: !account.email_verified_at.nil?,
        system_roles: account.system_roles_dataset.order(:name).select_map(:name),
        capabilities: account.capabilities
      }
      payload[:policy] = policy.summary if policy
      payload
    end

    def project_response(project, policy: nil)
      payload = {
        id: project.id,
        title: project.title,
        budget_cents: project.budget_cents,
        state: project.state
      }
      payload[:policy] = policy.summary if policy
      payload
    end

    def bid_submission_response(bid_submission, policy: nil)
      payload = {
        id: bid_submission.id,
        project_id: bid_submission.project_id,
        contractor_alias: bid_submission.contractor_alias
      }
      payload[:policy] = policy.summary if policy
      payload
    end

    def payment_response(payment, policy: nil)
      payload = {
        id: payment.id,
        bid_submission_id: payment.bid_submission_id,
        milestone_id: payment.milestone_id,
        project_id: payment.project_id,
        payment_type: payment.payment_type,
        status: payment.status,
        paid: payment.paid,
        method: payment[:method],
        reference: payment.reference,
        paid_at: payment.paid_at
      }
      payload[:policy] = policy.summary if policy
      payload
    end

    def milestone_response(milestone, policy: nil)
      payload = {
        id: milestone.id,
        project_id: milestone.project_id,
        title: milestone.title,
        description: milestone.description,
        budget_cents: milestone.budget_cents,
        assigned_bidder_id: milestone.assigned_bidder_id,
        state: milestone.state,
        sequence_order: milestone.sequence_order
      }
      payload[:policy] = policy.summary if policy
      payload
    end

    def bid_response(bid, policy: nil)
      payload = {
        id: bid.id,
        contractor: bid.contractor,
        project_id: bid.project_id,
        encrypted_bid: bid.encrypted_bid
      }
      payload[:policy] = policy.summary if policy
      payload
    end

    def account_policy(account)
      SecureBidding::Policies::AccountPolicy.new(auth_account, account, auth_scope: auth_scope)
    end

    def project_policy(project)
      SecureBidding::Policies::ProjectPolicy.new(auth_account, project, auth_scope: auth_scope)
    end

    def bid_submission_policy(bid_submission)
      SecureBidding::Policies::BidSubmissionPolicy.new(auth_account, bid_submission, auth_scope: auth_scope)
    end

    def payment_policy(payment)
      SecureBidding::Policies::PaymentPolicy.new(auth_account, payment, auth_scope: auth_scope)
    end

    def bid_policy(bid)
      SecureBidding::Policies::BidPolicy.new(auth_account, bid, auth_scope: auth_scope)
    end

    def milestone_policy(milestone)
      SecureBidding::Policies::MilestonePolicy.new(auth_account, milestone, auth_scope: auth_scope)
    end

    def project_membership_response(membership)
      {
        id: membership.id,
        project_id: membership.project_id,
        account_id: membership.account_id,
        role: membership.role.name
      }
    end

    def auth_account
      @auth_account
    end

    def auth_scope
      @auth_scope || AuthScope.new
    end

    def authorization
      @authorization
    end

    # rubocop:disable Metrics/BlockLength
    route do |r|
      # CORS headers for cross-origin requests
      # Prefer explicit CORS_ORIGIN; otherwise echo request Origin when present.
      # Use r.env (Rack env) which is always available in Roda route blocks
      request_origin = r.env['HTTP_ORIGIN'] || (r.request.env['HTTP_ORIGIN'] if r.respond_to?(:request) && r.request.respond_to?(:env))
      allowed_origin = ENV['CORS_ORIGIN'] || request_origin || '*'
      r.response.headers["Access-Control-Allow-Origin"] = allowed_origin
      r.response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, PATCH, OPTIONS"
      r.response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
      # Only allow credentials when we have an explicit origin (not '*')
      r.response.headers["Access-Control-Allow-Credentials"] = "true" unless allowed_origin == '*'

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
        @authorization = http_request.authenticated_account
        @auth_account = @authorization&.account
        @auth_scope = @authorization&.scope || AuthScope.new
      rescue InvalidTokenError
        r.halt(401, { message: 'Invalid auth token' }.to_json)
      rescue ExpiredTokenError
        r.halt(401, { message: 'Expired auth token' }.to_json)
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
