# frozen_string_literal: true

require 'roda'
require 'json'
require 'logger'
require_relative '../models/bid'
require_relative '../models/project'
require_relative '../models/bid_submission'

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

          r.on 'projects' do
            # GET /api/v1/projects - list all projects
            r.get true do
              projects = Project.order(:id).all.map do |project|
                { id: project.id, title: project.title, budget_cents: project.budget_cents }
              end
              { projects: projects }
            end

            # POST /api/v1/projects - create project
            r.post do
              payload = {}
              data = parse_json_request_body
              if response.status == 400
                data
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
