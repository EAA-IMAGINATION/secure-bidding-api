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
        policy = BidSubmissionPolicy.new(app.auth_account, nil)
        unless policy.can_list?
          app.response.status = 403
          return { error: 'Forbidden: only admins can list all bid submissions' }
        end

        bid_submissions = BidSubmission.order(:id).all.map do |bid_submission|
          {
            id: bid_submission.id,
            project_id: bid_submission.project_id,
            contractor_alias: bid_submission.contractor_alias
          }
        end

        { bid_submissions: bid_submissions }
      end

      def self.create_bid_submission(_req, app)
        if app.auth_account.nil?
          app.response.status = 403
          return { error: 'Login required to bid on projects' }
        end

        data = app.parse_json_request_body
        return data if app.response.status == 400

        validation = Validation::CreateBidSubmission.new.call(data.transform_keys(&:to_sym))
        if validation.failure?
          app.response.status = 400
          return { error: validation_error_message(validation) }
        end

        payload = validation.to_h
        project_id = payload[:project_id]
        contractor_alias = payload[:contractor_alias]
        plaintext_bid = payload[:plaintext_bid]

        allowed_keys = %w[project_id contractor_alias plaintext_bid]
        unless (data.keys.map(&:to_s) - allowed_keys).empty?
          app.response.status = 400
          return { error: 'Invalid bid submission attributes' }
        end

        unless app.valid_uuid?(project_id)
          app.response.status = 400
          return { error: 'project_id must be a UUID' }
        end

        project = Project[project_id]
        if project.nil?
          app.response.status = 400
          return { error: 'project_id does not reference an existing project' }
        end

        bid_submission = BidSubmission.new(project_id: project_id, contractor_alias: contractor_alias)
        policy = BidSubmissionPolicy.new(app.auth_account, bid_submission)

        unless policy.can_create?
          if project.state != 'published'
            app.response.status = 403
            { error: 'Project is not open for bidding' }
          elsif project_owner?(project, app.auth_account) || admin_account?(app.auth_account)
            app.response.status = 403
            { error: 'Forbidden: project owner or admin cannot bid on own project' }
          else
            app.response.status = 403
            { error: 'Forbidden: you cannot submit bids for this project' }
          end
        else
          begin
            bid_submission = BidSubmission.new(project_id: project_id, contractor_alias: contractor_alias)
            bid_submission.encrypt_bid(plaintext_bid)
            bid_submission.save

            app.class::APP_LOGGER.info("bid_submission_created id=#{bid_submission.id}")
            app.response.status = 201
            { id: bid_submission.id, status: 'created' }
          rescue Sequel::MassAssignmentRestriction
            app.response.status = 400
            { error: 'Invalid bid submission attributes' }
          end
        end
      end

      def self.show_bid_submission(_req, app, id)
        unless app.valid_uuid?(id)
          app.response.status = 404
          return { error: 'Bid submission not found' }
        end

        bid_submission = BidSubmission[id]
        if bid_submission
          policy = BidSubmissionPolicy.new(app.auth_account, bid_submission)
          unless policy.can_view?
            app.response.status = 403
            return { error: 'Forbidden: you do not have permission to view this bid submission' }
          end

          {
            id: bid_submission.id,
            project_id: bid_submission.project_id,
            contractor_alias: bid_submission.contractor_alias
          }
        else
          app.response.status = 404
          { error: 'Bid submission not found' }
        end
      end

      def self.validation_error_message(validation)
        errors = validation.errors.to_h
        missing = errors.select { |_field, messages| Array(messages).any? { |message| message.include?('missing') || message.include?('filled') } }.keys.map(&:to_s)
        return "#{join_fields(missing)} are required" if missing.any?

        fields = errors.keys.map(&:to_s).join(', ')
        messages = errors.values.flatten.join(', ')
        fields.empty? ? messages : "#{fields}: #{messages}"
      end

      def self.project_owner?(project, account)
        return false if account.nil?

        account_id = account[:account_id] || account['account_id'] || account.id
        owner_role = SecureBidding::Role.first(name: 'project_owner')
        return false if owner_role.nil?

        SecureBidding::ProjectMembership.first(
          account_id: account_id,
          project_id: project.id,
          role_id: owner_role.id
        ) != nil
      end

      def self.admin_account?(account)
        return false if account.nil?

        (account[:system_role] || account['system_role']) == 'admin'
      end

      def self.join_fields(fields)
        return fields.first if fields.length == 1
        return fields.join(' and ') if fields.length == 2

        "#{fields[0..-2].join(', ')}, and #{fields[-1]}"
      end
    end
  end
end
