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

module SecureBidding
  # Rack application for the secure bidding API.
  class App < Roda
    UUID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/.freeze
    APP_LOGGER = Logger.new($stdout)

    plugin :json
    plugin :halt
    plugin :all_verbs
    plugin :multi_route
    plugin :error_handler do |error|
      APP_LOGGER.error("Unhandled error: #{error.class} - #{error.message}")
      raise error
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

    # rubocop:disable Metrics/BlockLength
    route do |r|
      # Root route - health check
      r.root do
        { message: 'Secure Bidding API v1.0', status: 'ok' }
      end

      # SSL/TLS enforcement
      unless HttpRequest.new(r).secure?
        r.halt(403, { error: 'TLS/SSL Required' }.to_json)
      end

      r.on 'api' do
        r.on 'v1' do
          SecureBidding::Services::Roles::EnsureRoles.call

          r.on 'auth' do
            r.on 'authenticate' do
              # POST /api/v1/auth/authenticate
              r.post do
                credentials = HttpRequest.new(r).body_data
                auth_account = AuthenticateAccount.call(credentials)
                {
                  id: auth_account.id,
                  username: auth_account.username,
                  email: auth_account.email,
                  system_role: auth_account.system_role,
                  system_roles: auth_account.system_roles.map(&:name)
                }
              rescue AuthenticateAccount::UnauthorizedError => e
                APP_LOGGER.warn("Authentication failed: #{e.message}")
                r.halt 403, { error: 'Invalid credentials' }.to_json
              rescue StandardError => e
                APP_LOGGER.error("Authentication error: #{e.message}")
                r.halt 500, { error: 'Authentication service error' }.to_json
              end
            end
          end
          r.on 'bids' do
            # POST /api/v1/bids - Create a new bid
            r.post true do
              # Parse JSON request body
              data = JSON.parse(request.body.read)

              # Validate encrypted_bid is present and not empty
              encrypted_bid = data['encrypted_bid']
              if encrypted_bid.nil? || encrypted_bid.to_s.strip.empty?
                response.status = 400
                { error: 'encrypted_bid is required and cannot be empty' }
              else
                # Create and save the bid
                bid = Bid.new(
                  contractor: data['contractor'],
                  project_id: data['project_id'],
                  encrypted_bid: encrypted_bid
                )
                bid.save

                # Return 201 Created with bid_id and status
                response.status = 201
                { bid_id: bid.id, status: 'created' }
              end
            end

            # GET /api/v1/bids - Get all bid IDs
            r.get do
              r.is do
                bid_ids = Bid.all
                { bid_ids: bid_ids }
              end

              # GET /api/v1/bids/:id.json - Get a specific bid
              r.on String do |id|
                r.get do
                  bid = Bid.find(id)
                  if bid
                    {
                      id: bid.id,
                      contractor: bid.contractor,
                      project_id: bid.project_id,
                      encrypted_bid: bid.encrypted_bid
                    }
                  else
                    response.status = 404
                    { error: 'Bid not found' }
                  end
                end
              end
            end
          end

          r.on 'projects' do
            # GET /api/v1/projects - list all projects
            r.get true do
              projects = Project.order(:id).all.map do |project|
                { id: project.id, title: project.title, budget_cents: project.budget_cents }
              end
              { projects: projects }
            end

            # POST /api/v1/projects - create project
            r.post true do
              payload = {}
              data = parse_json_request_body
              if response.status == 400
                data
              elsif data.key?('owner_account_id')
                result = SecureBidding::Services::Projects::CreateProjectRequirement.call(data)
                if result[:ok]
                  response.status = 201
                  { id: result[:project].id, status: 'created' }
                else
                  response.status = result[:status]
                  { error: result[:error] }
                end
              else
                payload = data
                project = Project.new
                project.set(payload.transform_keys(&:to_sym))

                title = project.title
                budget_cents = project.budget_cents
                required_missing = title.to_s.strip.empty? || budget_cents.to_s.strip.empty?
                invalid_budget = !budget_cents.to_s.match?(/\A\d+\z/)

                if required_missing
                  response.status = 400
                  { error: 'title and budget_cents are required' }
                elsif invalid_budget
                  response.status = 400
                  { error: 'budget_cents must be a non-negative integer' }
                else
                  project.save
                  APP_LOGGER.info("project_created id=#{project.id}")
                  response.status = 201
                  { id: project.id, status: 'created' }
                end
              end
            rescue Sequel::MassAssignmentRestriction
              log_mass_assignment_attempt('project', payload, Project.allowed_columns)
              response.status = 400
              { error: 'Invalid project attributes' }
            rescue Sequel::UniqueConstraintViolation
              response.status = 400
              { error: 'project title must be unique' }
            end

            # GET /api/v1/projects/:id - single project
            r.on String do |id|
              r.on 'memberships' do
                r.get true do
                  unless valid_uuid?(id)
                    response.status = 404
                    next { error: 'Project not found' }
                  end

                  project = Project[id]
                  if project.nil?
                    response.status = 404
                    { error: 'Project not found' }
                  else
                    memberships = project.project_memberships_dataset.eager(:role).order(:id).all
                    {
                      project_id: project.id,
                      memberships: memberships.map { |membership| project_membership_response(membership) }
                    }
                  end
                end

                r.post true do
                  unless valid_uuid?(id)
                    response.status = 404
                    next { error: 'Project not found' }
                  end

                  data = parse_json_request_body
                  if response.status == 400
                    data
                  else
                    result = SecureBidding::Services::Projects::AssignProjectRole.call(
                      project_id: id,
                      account_id: data['account_id'],
                      role_name: data['role']
                    )
                    if result[:ok]
                      response.status = 201
                      project_membership_response(result[:membership])
                    else
                      response.status = result[:status]
                      { error: result[:error] }
                    end
                  end
                end
              end

              r.on 'bids' do
                r.post true do
                  unless valid_uuid?(id)
                    response.status = 404
                    next { error: 'Project not found' }
                  end

                  data = parse_json_request_body
                  if response.status == 400
                    data
                  else
                    result = SecureBidding::Services::Projects::CreateBidForProject.call(
                      project_id: id,
                      payload: data
                    )
                    if result[:ok]
                      response.status = 201
                      { id: result[:bid_submission].id, status: 'created' }
                    else
                      response.status = result[:status]
                      { error: result[:error] }
                    end
                  end
                end
              end

              r.get true do
                unless valid_uuid?(id)
                  response.status = 404
                  next { error: 'Project not found' }
                end

                project = Project[id]
                if project
                  { id: project.id, title: project.title, budget_cents: project.budget_cents }
                else
                  response.status = 404
                  { error: 'Project not found' }
                end
              end

              # GET /api/v1/projects/:id/bid_submissions - list bid submissions for a project
              r.on 'bid_submissions' do
                r.get true do
                  unless valid_uuid?(id)
                    response.status = 404
                    next { error: 'Project not found' }
                  end

                  project = Project[id]
                  if project
                    bid_submissions = project.bid_submissions_dataset.order(:id).all.map do |bid_submission|
                      {
                        id: bid_submission.id,
                        project_id: bid_submission.project_id,
                        contractor_alias: bid_submission.contractor_alias
                      }
                    end
                    { project_id: project.id, bid_submissions: bid_submissions }
                  else
                    response.status = 404
                    { error: 'Project not found' }
                  end
                end
              end
            end
          end

          r.on 'accounts' do
            # GET /api/v1/accounts - list accounts (without secret fields)
            r.get true do
              accounts = Account.order(:id).all.map do |account|
                {
                  id: account.id,
                  username: account.username,
                  system_role: account.system_role
                }
              end
              { accounts: accounts }
            end

            # POST /api/v1/accounts - create account with protected password/PII persistence
            r.post true do
              data = parse_json_request_body
              if response.status == 400
                data
              else
                result = SecureBidding::Services::Accounts::CreateAccount.call(data)
                if result[:ok]
                  response.status = 201
                  { id: result[:account].id, status: 'created' }
                else
                  response.status = result[:status]
                  { error: result[:error] }
                end
              end
            end

            # GET /api/v1/accounts/search?email=...&phone=...
            r.on 'search' do
              r.get true do
                result = SecureBidding::Services::Accounts::SearchAccounts.call(
                  email: request.params['email'],
                  phone: request.params['phone']
                )
                if result[:ok]
                  { accounts: result[:accounts].map { |account| account_response(account) } }
                else
                  response.status = result[:status]
                  { error: result[:error] }
                end
              end
            end

            # GET/PATCH /api/v1/accounts/:id
            r.on String do |id|
              r.on 'system_roles' do
                r.get true do
                  unless valid_uuid?(id)
                    response.status = 404
                    next { error: 'Account not found' }
                  end

                  account = SecureBidding::Services::Accounts::GetAccount.call(id)
                  if account
                    { account_id: account.id, roles: account.system_roles_dataset.order(:name).select_map(:name) }
                  else
                    response.status = 404
                    { error: 'Account not found' }
                  end
                end

                r.post true do
                  data = parse_json_request_body
                  if response.status == 400
                    data
                  else
                    result = SecureBidding::Services::Roles::AssignSystemRole.call(
                      account_id: id,
                      role_name: data['role']
                    )
                    if result[:ok]
                      response.status = 201
                      { account_id: id, role: result[:role], status: 'assigned' }
                    else
                      response.status = result[:status]
                      { error: result[:error] }
                    end
                  end
                end
              end

              r.get true do
                unless valid_uuid?(id)
                  response.status = 404
                  next { error: 'Account not found' }
                end

                account = SecureBidding::Services::Accounts::GetAccount.call(id)
                if account
                  account_response(account)
                else
                  response.status = 404
                  { error: 'Account not found' }
                end
              end

              r.patch true do
                unless valid_uuid?(id)
                  response.status = 404
                  next { error: 'Account not found' }
                end

                account = SecureBidding::Services::Accounts::GetAccount.call(id)
                if account.nil?
                  response.status = 404
                  { error: 'Account not found' }
                else
                  data = parse_json_request_body
                  if response.status == 400
                    data
                  else
                    result = SecureBidding::Services::Accounts::UpdateAccount.call(account, data)
                    if result[:ok]
                      { id: result[:account].id, status: 'updated' }
                    else
                      response.status = result[:status]
                      { error: result[:error] }
                    end
                  end
                end
              end
            end
          end

          r.on 'payments' do
            r.post true do
              data = parse_json_request_body
              if response.status == 400
                data
              else
                result = SecureBidding::Services::Payments::CreatePayment.call(data)
                if result[:ok]
                  response.status = 201
                  payment_response(result[:payment])
                else
                  response.status = result[:status]
                  { error: result[:error] }
                end
              end
            end

            r.on String do |id|
              r.get true do
                unless valid_uuid?(id)
                  response.status = 404
                  next { error: 'Payment not found' }
                end

                payment = Payment[id]
                if payment
                  payment_response(payment)
                else
                  response.status = 404
                  { error: 'Payment not found' }
                end
              end

              r.patch true do
                unless valid_uuid?(id)
                  response.status = 404
                  next { error: 'Payment not found' }
                end

                payment = Payment[id]
                if payment.nil?
                  response.status = 404
                  { error: 'Payment not found' }
                else
                  data = parse_json_request_body
                  if response.status == 400
                    data
                  else
                    result = SecureBidding::Services::Payments::UpdatePayment.call(payment: payment, payload: data)
                    if result[:ok]
                      payment_response(result[:payment])
                    else
                      response.status = result[:status]
                      { error: result[:error] }
                    end
                  end
                end
              end
            end
          end

          r.on 'bid_submissions' do
            # GET /api/v1/bid_submissions - list metadata for all bid submissions
            r.get true do
              bid_submissions = BidSubmission.order(:id).all.map do |bid_submission|
                {
                  id: bid_submission.id,
                  project_id: bid_submission.project_id,
                  contractor_alias: bid_submission.contractor_alias
                }
              end

              { bid_submissions: bid_submissions }
            end

            # POST /api/v1/bid_submissions - create encrypted bid submission
            r.post do
              payload = {}
              data = parse_json_request_body
              if response.status == 400
                data
              else
                payload = data
                project_id = payload['project_id']
                contractor_alias = payload['contractor_alias']
                plaintext_bid = payload['plaintext_bid']

                required_missing = [project_id, contractor_alias, plaintext_bid]
                                   .any? { |value| value.to_s.strip.empty? }
                if required_missing
                  response.status = 400
                  { error: 'project_id, contractor_alias, and plaintext_bid are required' }
                elsif !valid_uuid?(project_id)
                  response.status = 400
                  { error: 'project_id must be a UUID' }
                elsif Project[project_id].nil?
                  response.status = 400
                  { error: 'project_id does not reference an existing project' }
                else
                  bid_submission = BidSubmission.new
                  attributes = payload.reject { |key_name, _| key_name == 'plaintext_bid' }
                  bid_submission.set(attributes.transform_keys(&:to_sym))
                  bid_submission.encrypt_bid(plaintext_bid)
                  bid_submission.save

                  APP_LOGGER.info("bid_submission_created id=#{bid_submission.id}")
                  response.status = 201
                  { id: bid_submission.id, status: 'created' }
                end
              end
            rescue Sequel::MassAssignmentRestriction
              log_mass_assignment_attempt('bid_submission', payload, BidSubmission.allowed_columns + [:plaintext_bid])
              response.status = 400
              { error: 'Invalid bid submission attributes' }
            end

            # GET /api/v1/bid_submissions/:id - bid submission metadata only
            r.on String do |id|
              r.get do
                unless valid_uuid?(id)
                  response.status = 404
                  next { error: 'Bid submission not found' }
                end

                bid_submission = BidSubmission[id]
                if bid_submission
                  {
                    id: bid_submission.id,
                    project_id: bid_submission.project_id,
                    contractor_alias: bid_submission.contractor_alias
                  }
                else
                  response.status = 404
                  { error: 'Bid submission not found' }
                end
              end
            end
          end
        end
      end
    end

    # rubocop:enable Metrics/BlockLength
  end
end
