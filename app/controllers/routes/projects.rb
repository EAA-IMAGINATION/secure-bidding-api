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

            req.on 'accept' do
              req.post true do
                accept_project_ownership_request(req, app, id)
              end
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
        if app.auth_account
          # Authenticated user: return owned projects and published projects they can see
          projects = Project.where(state: 'published').order(:id).all.map do |project|
            { id: project.id, title: project.title, budget_cents: project.budget_cents, state: project.state }
          end
        else
          # Unauthenticated: return only published projects
          projects = Project.where(state: 'published').order(:id).all.map do |project|
            { id: project.id, title: project.title, budget_cents: project.budget_cents, state: project.state }
          end
        end
        { projects: projects }
      end

      def self.create_project(_req, app)
        unless app.auth_account
          app.response.status = 403
          return { error: 'Authentication required to create projects' }
        end

        payload = {}
        data = app.parse_json_request_body
        return data if app.response.status == 400

        create_project_from_auth_token(app, data)
      rescue Sequel::MassAssignmentRestriction
        app.log_mass_assignment_attempt('project', payload, Project.allowed_columns)
        app.response.status = 400
        { error: 'Invalid project attributes' }
      rescue Sequel::UniqueConstraintViolation
        app.response.status = 400
        { error: 'project title must be unique' }
      end

      def self.create_project_from_auth_token(app, data)
        project = Project.new
        project.set(data.transform_keys(&:to_sym))

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
          
          # Set owner as the authenticated account
          owner_account_id = app.auth_account[:account_id] || app.auth_account['account_id']
          role = SecureBidding::Role.first(name: 'project_owner')
          SecureBidding::ProjectMembership.create(
            account_id: owner_account_id,
            project_id: project.id,
            role_id: role.id
          )
          SecureBidding::AccountProject.create(
            account_id: owner_account_id,
            project_id: project.id,
            collaboration_role: 'owner'
          )

          app.class::APP_LOGGER.info("project_created id=#{project.id} owner=#{owner_account_id}")
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

        unless admin?(app) || owns_project?(app, id)
          app.response.status = 403
          return { error: 'Forbidden: only project owner or admin can manage project memberships' }
        end

        data = app.parse_json_request_body
        return data if app.response.status == 400

        result = SecureBidding::Services::Projects::AssignProjectRole.call(
          project_id: id,
          account_id: data['account_id'],
          role_name: data['role'],
          requested_by_admin: admin?(app)
        )
        if result[:ok]
          if result[:pending]
            app.response.status = 202
            return result[:request]
          end

          app.response.status = 201
          app.project_membership_response(result[:membership])
        else
          app.response.status = result[:status]
          { error: result[:error] }
        end
      end

      def self.accept_project_ownership_request(_req, app, id)
        unless app.valid_uuid?(id)
          app.response.status = 404
          return { error: 'Project not found' }
        end

        unless app.auth_account
          app.response.status = 403
          return { error: 'Authentication required to accept ownership request' }
        end

        project = Project[id]
        if project.nil?
          app.response.status = 404
          return { error: 'Project not found' }
        end

        account_id = app.auth_account[:account_id] || app.auth_account['account_id']
        collaboration = SecureBidding::AccountProject.first(
          account_id: account_id,
          project_id: id
        )
        if collaboration.nil? || collaboration.collaboration_role != 'pending_owner'
          app.response.status = 404
          return { error: 'No pending ownership request found' }
        end

        owner_role = SecureBidding::Role.first(name: 'project_owner')
        membership = SecureBidding::ProjectMembership.first(
          account_id: account_id,
          project_id: id,
          role_id: owner_role.id
        ) || SecureBidding::ProjectMembership.create(
          account_id: account_id,
          project_id: id,
          role_id: owner_role.id
        )
        collaboration.update(collaboration_role: 'owner')

        app.project_membership_response(membership)
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

      def self.update_project(_req, app, id)
        unless admin?(app) || owns_project?(app, id)
          app.response.status = 403
          return { error: 'Forbidden: only project owner or admin can update this project' }
        end

        unless app.valid_uuid?(id)
          app.response.status = 404
          return { error: 'Project not found' }
        end

        project = Project[id]
        return { error: 'Project not found' } if project.nil?

        begin
          update_data = app.parse_json_request_body
          return update_data if app.response.status == 400

          if update_data.key?('state') && !Project::VALID_STATES.include?(update_data['state'])
            app.response.status = 400
            return { error: "state must be 'saved' or 'published'" }
          end

          if update_data.key?('budget_cents') && !update_data['budget_cents'].to_s.match?(/\A\d+\z/)
            app.response.status = 400
            return { error: 'budget_cents must be a non-negative integer' }
          end

          project.update(update_data.transform_keys(&:to_sym))
          { id: project.id, status: 'updated' }
        rescue StandardError => e
          app.class::APP_LOGGER.error("Failed to update project #{id}: #{e.message}")
          app.response.status = 400
          { error: 'Failed to update project' }
        end
      end

      def self.delete_project(_req, app, id)
        unless admin?(app) || owns_project?(app, id)
          app.response.status = 403
          return { error: 'Forbidden: only project owner or admin can delete this project' }
        end

        unless app.valid_uuid?(id)
          app.response.status = 404
          return { error: 'Project not found' }
        end

        project = Project[id]
        if project.nil?
          app.response.status = 404
          { error: 'Project not found' }
        else
          project.delete
          { id: id, status: 'deleted' }
        end
      end

      def self.admin?(app)
        auth = app.auth_account
        return false unless auth

        if auth.is_a?(Hash)
          auth['system_role'] == 'admin' || auth[:system_role] == 'admin'
        else
          auth.system_role == 'admin'
        end
      end

      def self.owns_project?(app, project_id)
        return false unless app.auth_account

        account_id = app.auth_account[:account_id] || app.auth_account['account_id']
        project = Project[project_id]
        return false if project.nil?

        membership = ProjectMembership.where(
          project_id: project_id,
          account_id: account_id
        ).first

        if membership
          role = membership.role
          return true if role.name == 'project_owner'
        end

        collaboration = SecureBidding::AccountProject.first(
          project_id: project_id,
          account_id: account_id
        )
        return false if collaboration.nil?

        collaboration.collaboration_role == 'owner'
      end
    end
  end
end
