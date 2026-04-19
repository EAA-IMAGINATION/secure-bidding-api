# frozen_string_literal: true

require 'roda'
require 'json'
require 'logger'
require_relative '../models/bid'
require_relative '../models/account'
require_relative '../models/secret'

module SecureBidding
  # Rack application for the secure bidding API.
  class App < Roda
    UUID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/.freeze
    APP_LOGGER = Logger.new($stdout)

    plugin :json
    plugin :halt
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

    # rubocop:disable Metrics/BlockLength
    route do |r|
      # Root route - health check
      r.root do
        { message: 'Secure Bidding API v1.0', status: 'ok' }
      end

      r.on 'api' do
        r.on 'v1' do
          r.on 'bids' do
            # POST /api/v1/bids - Create a new bid
            r.post do
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

          r.on 'accounts' do
            # GET /api/v1/accounts - list all accounts
            r.get true do
              accounts = Account.order(:id).all.map do |account|
                { id: account.id, username: account.username, email: account.email }
              end
              { accounts: accounts }
            end

            # POST /api/v1/accounts - create account
            r.post do
              payload = {}
              data = parse_json_request_body
              if response.status == 400
                data
              else
                payload = data
                account = Account.new
                account.set(payload.transform_keys(&:to_sym))

                username = account.username
                email = account.email
                required_missing = [username, email].any? { |value| value.to_s.strip.empty? }

                if required_missing
                  response.status = 400
                  { error: 'username and email are required' }
                else
                  account.save
                  APP_LOGGER.info("account_created id=#{account.id}")
                  response.status = 201
                  { id: account.id, status: 'created' }
                end
              end
            rescue Sequel::MassAssignmentRestriction
              log_mass_assignment_attempt('account', payload, Account.allowed_columns)
              response.status = 400
              { error: 'Invalid account attributes' }
            rescue Sequel::UniqueConstraintViolation
              response.status = 400
              { error: 'username and email must be unique' }
            end

            # GET /api/v1/accounts/:id - single account
            r.on String do |id|
              r.get true do
                unless valid_uuid?(id)
                  response.status = 404
                  next { error: 'Account not found' }
                end

                account = Account[id]
                if account
                  { id: account.id, username: account.username, email: account.email }
                else
                  response.status = 404
                  { error: 'Account not found' }
                end
              end

              # GET /api/v1/accounts/:id/secrets - list secrets for a single account
              r.on 'secrets' do
                r.get true do
                  unless valid_uuid?(id)
                    response.status = 404
                    next { error: 'Account not found' }
                  end

                  account = Account[id]
                  if account
                    secrets = account.secrets_dataset.order(:id).all.map do |secret|
                      { id: secret.id, account_id: secret.account_id, title: secret.title }
                    end
                    { account_id: account.id, secrets: secrets }
                  else
                    response.status = 404
                    { error: 'Account not found' }
                  end
                end
              end
            end
          end

          r.on 'secrets' do
            # GET /api/v1/secrets - list metadata for all secrets
            r.get true do
              secrets = Secret.order(:id).all.map do |secret|
                { id: secret.id, account_id: secret.account_id, title: secret.title }
              end

              { secrets: secrets }
            end

            # POST /api/v1/secrets - Create encrypted secret
            r.post do
              payload = {}
              data = parse_json_request_body
              if response.status == 400
                data
              else
                payload = data
                account_id = payload['account_id']
                title = payload['title']
                plaintext = payload['plaintext']

                required_missing = [account_id, title, plaintext].any? { |value| value.to_s.strip.empty? }
                if required_missing
                  response.status = 400
                  { error: 'account_id, title, and plaintext are required' }
                elsif !valid_uuid?(account_id)
                  response.status = 400
                  { error: 'account_id must be a UUID' }
                elsif Account[account_id].nil?
                  response.status = 400
                  { error: 'account_id does not reference an existing account' }
                else
                  secret = Secret.new
                  secret.set(payload.reject { |key_name, _| key_name == 'plaintext' }.transform_keys(&:to_sym))
                  secret.encrypt_data(plaintext)
                  secret.save

                  APP_LOGGER.info("secret_created id=#{secret.id}")
                  response.status = 201
                  { id: secret.id, status: 'created' }
                end
              end
            rescue Sequel::MassAssignmentRestriction
              log_mass_assignment_attempt('secret', payload, Secret.allowed_columns + [:plaintext])
              response.status = 400
              { error: 'Invalid secret attributes' }
            end

            # GET /api/v1/secrets/:id - secret metadata only
            r.on String do |id|
              r.get do
                unless valid_uuid?(id)
                  response.status = 404
                  next { error: 'Secret not found' }
                end

                secret = Secret[id]
                if secret
                  { id: secret.id, account_id: secret.account_id, title: secret.title }
                else
                  response.status = 404
                  { error: 'Secret not found' }
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
