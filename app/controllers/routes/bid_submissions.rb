# frozen_string_literal: true

module SecureBidding
  module Routes
    # Handles bid_submissions endpoints and related actions.
    module BidSubmissions
      def self.call(req, app)
        req.on 'bid_submissions' do
          handle_bid_submissions(req, app)
        end
      end

      def self.handle_bid_submissions(req, app)
        req.get true do
          list_bid_submissions(req, app)
        end

        req.post do
          create_bid_submission(req, app)
        end

        req.on String do |id|
          req.get do
            show_bid_submission(req, app, id)
          end
        end
      end

      def self.list_bid_submissions(_req, app)
        bid_submissions = SecureBidding::Policies::BidSubmissionPolicy::Scope.new(app.auth_account, BidSubmission).resolve.map do |bid_submission|
          app.bid_submission_response(bid_submission, policy: app.bid_submission_policy(bid_submission))
        end

        { bid_submissions: bid_submissions }
      end

      def self.create_bid_submission(_req, app)
        data = app.parse_json_request_body
        return data if app.response.status == 400

        payload = data
        SecureBidding::Forms::BidSubmissionsCreateForm.new.call(data)
        project_id = payload['project_id'] || payload[:project_id]
        contractor_alias = payload['contractor_alias'] || payload[:contractor_alias]
        plaintext_bid = payload['plaintext_bid'] || payload[:plaintext_bid]

        required_missing = [project_id, contractor_alias, plaintext_bid].any? { |value| value.to_s.strip.empty? }
        if required_missing
          app.response.status = 400
          { error: 'project_id, contractor_alias, and plaintext_bid are required' }
        elsif !app.valid_uuid?(project_id)
          app.response.status = 400
          { error: 'project_id must be a UUID' }
        elsif Project[project_id].nil?
          app.response.status = 404
          { error: 'project_id does not reference an existing project' }
        elsif Project[project_id].state != 'published'
          app.response.status = 403
          { error: 'Project is not open for bidding' }
        elsif app.auth_account.nil?
          app.response.status = 401
          { error: 'Login required to bid on projects' }
        elsif project_owner?(Project[project_id], app.auth_account)
          app.response.status = 403
          { error: 'Project owner cannot bid on own project' }
        else
          bid_submission = BidSubmission.new
          attributes = payload.reject { |key_name, _| key_name.to_s == 'plaintext_bid' }
          bid_submission.set(attributes.transform_keys(&:to_sym))
          bid_submission.encrypt_bid(plaintext_bid)
          bid_submission.save

          app.class::APP_LOGGER.info("bid_submission_created id=#{bid_submission.id}")
          app.response.status = 201
          { id: bid_submission.id, status: 'created' }
        end
      rescue Sequel::MassAssignmentRestriction
        app.log_mass_assignment_attempt('bid_submission', payload, BidSubmission.allowed_columns + [:plaintext_bid])
        app.response.status = 400
        { error: 'Invalid bid submission attributes' }
      end

      def self.project_owner?(project, auth_account)
        account_id = auth_account[:account_id] || auth_account['account_id']
        owner_role = Role.ensure_role('project_owner')
        return false if account_id.nil? || owner_role.nil?

        ProjectMembership.first(
          account_id: account_id,
          project_id: project.id,
          role_id: owner_role.id
        ) != nil
      end

      def self.show_bid_submission(_req, app, id)
        unless app.valid_uuid?(id)
          app.response.status = 404
          return { error: 'Bid submission not found' }
        end

        bid_submission = BidSubmission[id]
        if bid_submission && app.bid_submission_policy(bid_submission).show?
          app.bid_submission_response(bid_submission, policy: app.bid_submission_policy(bid_submission))
        else
          app.response.status = 404
          { error: 'Bid submission not found' }
        end
      end
    end
  end
end
