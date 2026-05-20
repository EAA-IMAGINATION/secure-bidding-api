# frozen_string_literal: true

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

          req.on 'bid_submissions' do
            req.get true do
              list_project_bid_submissions(req, app, id)
            end
          end
        end
      end

      def self.list_projects(_req, _app)
        projects = Project.where(state: 'published').order(:id).all.map do |project|
          { id: project.id, title: project.title, budget_cents: project.budget_cents, state: project.state }
        end
        { projects: projects }
      end

      def self.create_project(_req, app)
        payload = {}
        data = app.parse_json_request_body
        return data if app.response.status == 400

        if data.key?('owner_account_id')
          create_project_with_owner(app, data)
        else
          create_project_from_payload(app, data)
        end
      rescue Sequel::MassAssignmentRestriction
        app.log_mass_assignment_attempt('project', payload, Project.allowed_columns)
        app.response.status = 400
        { error: 'Invalid project attributes' }
      rescue Sequel::UniqueConstraintViolation
        app.response.status = 400
        { error: 'project title must be unique' }
      end

      def self.create_project_with_owner(app, data)
        result = SecureBidding::Services::Projects::CreateProjectRequirement.call(data)
        if result[:ok]
          app.response.status = 201
          { id: result[:project].id, status: 'created' }
        else
          app.response.status = result[:status]
          { error: result[:error] }
        end
      end

      def self.create_project_from_payload(app, payload)
        project = Project.new
        project.set(payload.transform_keys(&:to_sym))

        title = project.title
        budget_cents = project.budget_cents
        state = project.state
        required_missing = title.to_s.strip.empty? || budget_cents.to_s.strip.empty?
        invalid_budget = !budget_cents.to_s.match?(/\A\d+\z/)
        invalid_state = !state.nil? && !Project::VALID_STATES.include?(state)

        if required_missing
          app.response.status = 400
          { error: 'title and budget_cents are required' }
        elsif invalid_budget
          app.response.status = 400
          { error: 'budget_cents must be a non-negative integer' }
        elsif invalid_state
          app.response.status = 400
          { error: "state must be 'saved' or 'published'" }
        else
          project.save
          app.class::APP_LOGGER.info("project_created id=#{project.id}")
          app.response.status = 201
          { id: project.id, status: 'created' }
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
          { error: 'Project not found' }
        else
          memberships = project.project_memberships_dataset.eager(:role).order(:id).all
          {
            project_id: project.id,
            memberships: memberships.map { |membership| app.project_membership_response(membership) }
          }
        end
      end

      def self.assign_project_role(_req, app, id)
        unless app.valid_uuid?(id)
          app.response.status = 404
          return { error: 'Project not found' }
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
        if project && project.state == 'published'
          { id: project.id, title: project.title, budget_cents: project.budget_cents, state: project.state }
        else
          app.response.status = 404
          { error: 'Project not found' }
        end
      end

      def self.list_project_bid_submissions(_req, app, id)
        unless app.valid_uuid?(id)
          app.response.status = 404
          return { error: 'Project not found' }
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
          app.response.status = 404
          { error: 'Project not found' }
        end
      end
    end
  end
end
