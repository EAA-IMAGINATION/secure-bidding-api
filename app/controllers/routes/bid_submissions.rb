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
        result = SecureBidding::Forms::BidSubmissionsCreateForm.new.call(data)
        validation_error = SecureBidding::FormValidation.response_for(app, result)
        return validation_error if validation_error

        project_id = payload['project_id'] || payload[:project_id]
        contractor_alias = payload['contractor_alias'] || payload[:contractor_alias]
        encrypted_bid_amount = payload['encrypted_bid_amount'] || payload[:encrypted_bid_amount]
        encrypted_proposal_text = payload['encrypted_proposal_text'] || payload[:encrypted_proposal_text]
        encrypted_document = payload['encrypted_document'] || payload[:encrypted_document]
        document_file_hash = payload['document_file_hash'] || payload[:document_file_hash]

        required_missing = [project_id, contractor_alias, encrypted_bid_amount, encrypted_proposal_text].any? do |value|
          value.to_s.strip.empty?
        end
        project = Project[project_id] if app.valid_uuid?(project_id)

        if required_missing
          app.response.status = 400
          { error: 'project_id, contractor_alias, encrypted_bid_amount, and encrypted_proposal_text are required' }
        elsif !app.valid_uuid?(project_id)
          app.response.status = 400
          { error: 'project_id must be a UUID' }
        elsif project.nil?
          app.response.status = 404
          { error: 'project_id does not reference an existing project' }
        elsif project.state != 'published'
          app.response.status = 403
          { error: 'Project is not open for bidding' }
        elsif app.auth_account.nil?
          app.response.status = 401
          { error: 'Login required to bid on projects' }
        elsif project_owner?(project, app.auth_account)
          app.response.status = 403
          { error: 'Project owner cannot bid on own project' }
        elsif required_documents_for(project).any? && !ClientCiphertext.valid_envelope?(encrypted_document)
          app.response.status = 400
          { error: 'All required documents must be uploaded before submitting a bid' }
        elsif required_documents_for(project).any? && !required_documents_satisfied?(required_documents_for(project), document_file_hash)
          app.response.status = 400
          { error: 'All required documents must be uploaded before submitting a bid' }
        else
          auth_account_id = app.auth_account[:account_id] || app.auth_account['account_id']
          bid_payload = payload.transform_keys(&:to_s).merge('bidder_account_id' => auth_account_id)
          result = SecureBidding::Services::Projects::CreateBidForProject.call(
            project_id: project_id,
            payload: bid_payload,
            auth_account: app.auth_account
          )
          unless result[:ok]
            app.response.status = result[:status]
            return { error: result[:error] }
          end

          bid_submission = result[:bid_submission]
          action = result[:updated] ? 'updated' : 'created'
          app.class::APP_LOGGER.info("bid_submission_#{action} id=#{bid_submission.id}")
          app.response.status = result[:updated] ? 200 : 201
          { id: bid_submission.id, status: action }
        end
      rescue Sequel::MassAssignmentRestriction
        app.log_mass_assignment_attempt(
          'bid_submission',
          payload,
          BidSubmission.allowed_columns + %i[encrypted_bid_amount encrypted_proposal_text]
        )
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

      def self.required_documents_for(project)
        value = project.required_documents.to_s.strip
        return [] if value.empty?

        JSON.parse(value)
      rescue JSON::ParserError
        []
      end

      def self.required_documents_satisfied?(required_documents, document_file_hash)
        submitted = document_file_hash.to_s.split('|').map do |entry|
          entry.split(':', 2).first.to_s.strip
        end

        required_documents.all? { |document_name| submitted.include?(document_name.to_s.strip) }
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
