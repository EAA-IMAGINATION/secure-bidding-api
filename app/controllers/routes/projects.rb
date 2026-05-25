# frozen_string_literal: true

require 'time'

module SecureBidding
  module Routes
    # Handles projects listing, creation and nested project routes.
    module Projects
      def self.call(req, app)
        req.on 'projects' do
          handle_projects(req, app)
        end
      end

      def self.handle_projects(req, app)
        req.get true do
          list_projects(req, app)
        end

        req.post true do
          create_project(req, app)
        end

        req.on String do |id|
          req.on 'memberships' do
            req.get true do
              list_project_memberships(req, app, id)
            end

            req.post true do
              assign_project_role(req, app, id)
            end
          end

          req.on 'bids' do
            req.post true do
              create_bid_for_project(req, app, id)
            end
          end

          req.get true do
            get_project(req, app, id)
          end

          req.patch true do
            update_project(req, app, id)
          end

          req.delete true do
            delete_project(req, app, id)
          end

          req.on 'bid_submissions' do
            req.get true do
              list_project_bid_submissions(req, app, id)
            end
          end
        end
      end

      def self.list_projects(_req, app)
        scope = ProjectPolicy::Scope.new(app.auth_account, Project)
        projects = scope.resolve.order(:id).all.map do |project|
          policy = ProjectPolicy.new(app.auth_account, project)
          bid_count = if policy.can_view_bid_count? || policy.can_view_bid_submissions?
                        project.bid_count
                      end
          {
            id: project.id,
            title: project.title,
            budget_cents: project.budget_cents,
            state: project.state,
            submission_deadline_at: project.submission_deadline_at,
            bid_count: bid_count,
            policy: policy.summary
          }
        end
        { projects: projects }
      end

      def self.create_project(_req, app)
        policy = ProjectPolicy.new(app.auth_account, nil)
        unless policy.can_create?
          app.response.status = 403
          return { error: 'Forbidden: only members can create projects' }
        end

        data = app.parse_json_request_body
        return data if app.response.status == 400

        validation = Validation::CreateProject.new.call(data.transform_keys(&:to_sym))
        if validation.failure?
          app.response.status = 400
          return { error: validation_error_message(validation) }
        end
        payload = validation.to_h

        allowed_keys = %w[title budget_cents state submission_deadline_at]
        unless (data.keys.map(&:to_s) - allowed_keys).empty?
          app.response.status = 400
          return { error: 'Invalid project attributes' }
        end

        begin
          attributes = {
            title: payload[:title],
            budget_cents: payload[:budget_cents]
          }
          attributes[:state] = payload[:state] if payload.key?(:state)
          project = Project.new(attributes)
          project.submission_deadline_at = parse_submission_deadline(payload[:submission_deadline_at]) if payload.key?(:submission_deadline_at)
          project.save

          owner_account_id = app.auth_account[:account_id] || app.auth_account['account_id']
          role = SecureBidding::Role.first(name: 'project_owner')
          SecureBidding::ProjectMembership.create(
            account_id: owner_account_id,
            project_id: project.id,
            role_id: role.id
          )

          app.class::APP_LOGGER.info("project_created id=#{project.id} owner=#{owner_account_id}")
          app.response.status = 201
          { id: project.id, status: 'created' }
        rescue Sequel::UniqueConstraintViolation
          app.response.status = 400
          { error: 'project title must be unique' }
        rescue StandardError => e
          app.response.status = 400
          { error: e.message }
        end
      end

      def self.list_project_memberships(_req, app, id)
        unless app.valid_uuid?(id)
          app.response.status = 404
          return { error: 'Project not found' }
        end

        project = Project[id]
        if project.nil?
          app.response.status = 404
          return { error: 'Project not found' }
        end

        policy = ProjectPolicy.new(app.auth_account, project)
        unless policy.can_view_memberships?
          app.response.status = 403
          return { error: 'Forbidden: you cannot view memberships for this project' }
        end

        memberships = project.project_memberships_dataset.eager(:role).order(:id).all
        {
          project_id: project.id,
          memberships: memberships.map { |membership| app.project_membership_response(membership) }
        }
      end

      def self.assign_project_role(_req, app, id)
        unless app.valid_uuid?(id)
          app.response.status = 404
          return { error: 'Project not found' }
        end

        project = Project[id]
        if project.nil?
          app.response.status = 404
          return { error: 'Project not found' }
        end

        policy = ProjectPolicy.new(app.auth_account, project)
        unless policy.can_assign_role?
          app.response.status = 403
          return { error: 'Forbidden: only project owners or admins can assign roles' }
        end

        data = app.parse_json_request_body
        return data if app.response.status == 400

        result = SecureBidding::Services::Projects::AssignProjectRole.call(
          project_id: id,
          account_id: data['account_id'],
          role_name: data['role']
        )
        if result[:ok]
          app.response.status = 201
          app.project_membership_response(result[:membership])
        else
          app.response.status = result[:status]
          { error: result[:error] }
        end
      end

      def self.create_bid_for_project(_req, app, id)
        unless app.valid_uuid?(id)
          app.response.status = 404
          return { error: 'Project not found' }
        end

        project = Project[id]
        if project.nil?
          app.response.status = 404
          return { error: 'Project not found' }
        end

        policy = ProjectPolicy.new(app.auth_account, project)
        unless policy.can_submit_bid?
          app.response.status = 403
          if app.auth_account.nil?
            return { error: 'Login required to bid on projects' }
          end

          if project.state != 'published'
            return { error: 'Project is not open for bidding' }
          end

          if project_owner?(project, app.auth_account) || app.auth_account[:system_role] == 'admin' || app.auth_account['system_role'] == 'admin'
            return { error: 'Project owner cannot bid on own project' }
          end

          { error: 'Forbidden: you cannot submit bids for this project' }
        end

        data = app.parse_json_request_body
        return data if app.response.status == 400

        result = SecureBidding::Services::Projects::CreateBidForProject.call(
          project_id: id,
          payload: data,
          auth_account: app.auth_account
        )
        if result[:ok]
          app.response.status = 201
          { id: result[:bid_submission].id, status: 'created' }
        else
          app.response.status = result[:status]
          { error: result[:error] }
        end
      end

      def self.get_project(_req, app, id)
        unless app.valid_uuid?(id)
          app.response.status = 404
          return { error: 'Project not found' }
        end

        project = Project[id]
        if project.nil?
          app.response.status = 404
          return { error: 'Project not found' }
        end

        policy = ProjectPolicy.new(app.auth_account, project)
        unless policy.can_view?
          app.response.status = 404
          return { error: 'Project not found' }
        end

        {
          id: project.id,
          title: project.title,
          budget_cents: project.budget_cents,
          state: project.state,
          submission_deadline_at: project.submission_deadline_at,
          bid_count: (policy.can_view_bid_count? || policy.can_view_bid_submissions?) ? project.bid_count : nil,
          policy: policy.summary
        }
      end

      def self.list_project_bid_submissions(_req, app, id)
        unless app.valid_uuid?(id)
          app.response.status = 404
          return { error: 'Project not found' }
        end

        project = Project[id]
        if project.nil?
          app.response.status = 404
          return { error: 'Project not found' }
        end

        policy = ProjectPolicy.new(app.auth_account, project)
        unless policy.can_view_bid_count? || policy.can_view_bid_submissions?
          app.response.status = 403
          return { error: 'Forbidden' }
        end

        if policy.can_view_bid_count?
          { project_id: project.id, bid_count: project.bid_count }
        else
          bid_submissions = project.bid_submissions_dataset.order(:id).all.map do |bid_submission|
            {
              id: bid_submission.id,
              project_id: bid_submission.project_id,
              contractor_alias: bid_submission.contractor_alias
            }
          end
          { project_id: project.id, bid_submissions: bid_submissions }
        end
      end

      def self.update_project(_req, app, id)
        unless app.valid_uuid?(id)
          app.response.status = 404
          return { error: 'Project not found' }
        end

        project = Project[id]
        if project.nil?
          app.response.status = 404
          return { error: 'Project not found' }
        end

        policy = ProjectPolicy.new(app.auth_account, project)
        unless policy.can_edit?
          app.response.status = 403
          return { error: 'Forbidden: only project owner or admin can update this project' }
        end

        data = app.parse_json_request_body
        return data if app.response.status == 400

        validation = Validation::UpdateProject.new.call(data.transform_keys(&:to_sym))
        if validation.failure?
          app.response.status = 400
          return { error: validation_error_message(validation) }
        end
        payload = validation.to_h

        allowed_keys = %w[title budget_cents state submission_deadline_at]
        unless (data.keys.map(&:to_s) - allowed_keys).empty?
          app.response.status = 400
          return { error: 'Invalid project attributes' }
        end

        begin
          update_payload = payload.dup
          update_payload.delete(:submission_deadline_at)
          project.update(update_payload)
          project.submission_deadline_at = parse_submission_deadline(payload[:submission_deadline_at]) if payload.key?(:submission_deadline_at)
          project.save
          { id: project.id, status: 'updated' }
        rescue StandardError => e
          app.class::APP_LOGGER.error("Failed to update project #{id}: #{e.message}")
          app.response.status = 400
          { error: 'Failed to update project' }
        end
      end

      def self.delete_project(_req, app, id)
        unless app.valid_uuid?(id)
          app.response.status = 404
          return { error: 'Project not found' }
        end

        project = Project[id]
        if project.nil?
          app.response.status = 404
          return { error: 'Project not found' }
        end

        policy = ProjectPolicy.new(app.auth_account, project)
        unless policy.can_delete?
          app.response.status = 403
          return { error: 'Forbidden: only project owner or admin can delete this project' }
        end

        project.delete
        { id: id, status: 'deleted' }
      end

      def self.validation_error_message(validation)
        errors = validation.errors.to_h
        missing = errors.select { |_field, messages| Array(messages).any? { |message| message.include?('missing') || message.include?('filled') } }.keys.map(&:to_s)
        return "#{join_fields(missing)} are required" if missing.any?

        if errors.key?(:state) && Array(errors[:state]).any? { |message| message.include?('one of') }
          return "state must be 'saved' or 'published'"
        end

        if errors.key?(:budget_cents) && Array(errors[:budget_cents]).any? { |message| message.include?('integer') || message.include?('greater') }
          return 'budget_cents must be a positive integer'
        end

        fields = errors.keys.map(&:to_s).join(', ')
        messages = errors.values.flatten.join(', ')
        fields.empty? ? messages : "#{fields}: #{messages}"
      end

      def self.parse_submission_deadline(value)
        return nil if value.nil? || value.to_s.strip.empty?

        Time.iso8601(value.to_s)
      rescue ArgumentError
        raise ArgumentError, 'submission_deadline_at must be an ISO8601 timestamp'
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

      def self.join_fields(fields)
        return fields.first if fields.length == 1
        return fields.join(' and ') if fields.length == 2

        "#{fields[0..-2].join(', ')}, and #{fields[-1]}"
      end
    end
  end
end
