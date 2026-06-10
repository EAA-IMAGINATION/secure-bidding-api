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

          req.on 'bid_count' do
            req.get true do
              get_project_bid_count(req, app, id)
            end
          end

          req.on 'integrity_snapshot' do
            req.get true do
              get_project_integrity_snapshot(req, app, id)
            end
          end

          req.on 'milestones' do
            req.get true do
              list_project_milestones(req, app, id)
            end

            req.post true do
              create_project_milestone(req, app, id)
            end
          end

          req.on 'award' do
            req.post true do
              award_project_bid(req, app, id)
            end
          end

          req.on 'request_payment' do
            req.post true do
              request_project_payment(req, app, id)
            end
          end

          req.on 'process_payment' do
            req.post true do
              process_project_payment(req, app, id)
            end
          end

          req.on 'acknowledge_payment' do
            req.post true do
              acknowledge_project_payment(req, app, id)
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
        projects = SecureBidding::Policies::ProjectPolicy::Scope.new(app.auth_account, Project).resolve
        visible = projects.select { |project| app.project_policy(project).show? }
        payloads = visible.map do |project|
          app.project_response(project, policy: app.project_policy(project))
        end
        { projects: payloads }
      end

      def self.create_project(_req, app)
        unless app.auth_account
          app.response.status = 401
          return { error: 'Authentication required to create projects' }
        end

        policy = app.project_policy(Project.new)
        unless policy.create?
          app.response.status = 403
          role = app.auth_account&.dig(:system_role) || app.auth_account&.dig('system_role')
          if role == 'admin' || role == 'system_admin'
            return { error: 'Forbidden: system administrators cannot create projects' }
          end
          return { error: 'Forbidden: verify your email before creating projects' }
        end

        data = app.parse_json_request_body
        return data if app.response.status == 400

        result = SecureBidding::Forms::ProjectsCreateForm.new.call(data)
        validation_error = SecureBidding::FormValidation.response_for(app, result)
        return validation_error if validation_error

        create_project_from_auth_token(app, data)
      rescue Sequel::MassAssignmentRestriction
        app.log_mass_assignment_attempt('project', data, Project.allowed_columns)
        app.response.status = 400
        { error: 'Invalid project attributes' }
      rescue Sequel::UniqueConstraintViolation
        app.response.status = 400
        { error: 'project title must be unique' }
      end

      def self.create_project_from_auth_token(app, data)
        project = Project.new
        project.set(normalize_project_payload(data).transform_keys(&:to_sym))

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
          role = SecureBidding::Role.ensure_role('project_owner')
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
        elsif app.project_policy(project).view_memberships?
          memberships = project.project_memberships_dataset.eager(:role).order(:id).all
          {
            project_id: project.id,
            memberships: memberships.map { |membership| app.project_membership_response(membership) }
          }
        else
          app.response.status = 403
          { error: 'Forbidden: only project owner or admin can view memberships' }
        end
      end

      def self.assign_project_role(_req, app, id)
        unless app.valid_uuid?(id)
          app.response.status = 404
          return { error: 'Project not found' }
        end

        data = app.parse_json_request_body
        return data if app.response.status == 400

        project = Project[id]
        if project.nil?
          app.response.status = 404
          return { error: 'Project not found' }
        end

        unless app.project_policy(project).manage_memberships?
          app.response.status = 403
          return { error: 'Forbidden: only project owner or admin can manage project memberships' }
        end

        result = SecureBidding::Forms::ProjectsRoleForm.new.call(data)
        validation_error = SecureBidding::FormValidation.response_for(app, result)
        return validation_error if validation_error

        result = SecureBidding::Services::Projects::AssignProjectRole.call(
          project_id: id,
          account_id: data['account_id'] || data[:account_id],
          role_name: data['role'] || data[:role],
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
          app.response.status = 401
          return { error: 'Authentication required to accept ownership request' }
        end

        project = Project[id]
        if project.nil?
          app.response.status = 404
          return { error: 'Project not found' }
        end

        unless app.project_policy(project).accept_ownership?
          app.response.status = 404
          return { error: 'No pending ownership request found' }
        end

        account_id = app.auth_account[:account_id] || app.auth_account['account_id']
        collaboration = SecureBidding::AccountProject.first(account_id: account_id, project_id: id)
        owner_role = SecureBidding::Role.ensure_role('project_owner')
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

        project = Project[id]
        if project.nil?
          app.response.status = 404
          return { error: 'Project not found' }
        end

        if app.auth_account.nil?
          app.response.status = 401
          return { error: 'Authentication required to bid on projects' }
        end

        bidder_account_id = data['bidder_account_id'] || data[:bidder_account_id]
        if bidder_account_id.to_s.strip.empty?
          app.response.status = 400
          return { error: 'bidder_account_id, contractor_alias, encrypted_bid_amount, and encrypted_proposal_text are required' }
        elsif !bidder_account_id.to_s.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
          app.response.status = 400
          return { error: 'bidder_account_id must be a UUID' }
        end

        if project.state != 'published'
          app.response.status = 403
          return { error: 'Project is not open for bidding' }
        end

        if SecureBidding::Services::Projects::CreateBidForProject.owner_of_project?(project.id, app.auth_account[:account_id] || app.auth_account['account_id'])
          app.response.status = 403
          return { error: 'Project owner cannot bid on own project' }
        end

        result = SecureBidding::Forms::ProjectsBidForm.new.call(data)
        validation_error = SecureBidding::FormValidation.response_for(app, result)
        return validation_error if validation_error

        result = SecureBidding::Services::Projects::CreateBidForProject.call(
          project_id: id,
          payload: data.transform_keys(&:to_s),
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

        policy = app.project_policy(project)
        if policy.show?
          app.project_response(project, policy: policy)
        else
          app.response.status = 403
          { error: 'Forbidden: you do not have access to this project' }
        end
      end

      def self.get_project_bid_count(_req, app, id)
        unless app.valid_uuid?(id)
          app.response.status = 404
          return { error: 'Project not found' }
        end

        project = Project[id]
        if project && app.project_policy(project).view_bid_count?
          {
            project_id: project.id,
            bid_count: project.bid_submissions_dataset.count
          }
        else
          app.response.status = 404
          { error: 'Project not found' }
        end
      end

      def self.get_project_integrity_snapshot(_req, app, id)
        unless app.valid_uuid?(id)
          app.response.status = 404
          return { error: 'Project not found' }
        end

        project = Project[id]
        if project.nil?
          app.response.status = 404
          return { error: 'Project not found' }
        end

        unless SecureBidding::Policies::ProjectPolicy.bidding_closed_for?(project)
          app.response.status = 404
          return { error: 'Integrity snapshot not yet available' }
        end

        snapshot = SecureBidding::IntegritySnapshot.where(project_id: project.id).first
        if snapshot.nil?
          SecureBidding::Services::Projects::GenerateIntegritySnapshot.call(project)
          snapshot = SecureBidding::IntegritySnapshot.where(project_id: project.id).first
        end

        if snapshot.nil?
          app.response.status = 404
          return { error: 'Integrity snapshot not yet available' }
        end

        {
          project_id: project.id,
          canonical_hash: snapshot.canonical_hash,
          snapshot_taken_at: snapshot.snapshot_taken_at.iso8601
        }
      end

      def self.list_project_milestones(_req, app, id)
        unless app.valid_uuid?(id)
          app.response.status = 404
          return { error: 'Project not found' }
        end

        project = Project[id]
        if project && app.project_policy(project).manage_milestones?
          milestones = project.milestones_dataset.order(:sequence_order, :id).all.map do |milestone|
            app.milestone_response(milestone, policy: app.milestone_policy(milestone))
          end
          { project_id: project.id, milestones: milestones }
        else
          app.response.status = 404
          { error: 'Project not found' }
        end
      end

      def self.create_project_milestone(_req, app, id)
        unless app.valid_uuid?(id)
          app.response.status = 404
          return { error: 'Project not found' }
        end

        project = Project[id]
        if project.nil?
          app.response.status = 404
          return { error: 'Project not found' }
        end

        unless app.project_policy(project).manage_milestones?
          app.response.status = 403
          return { error: 'Forbidden: only project owner or admin can manage milestones' }
        end

        data = app.parse_json_request_body
        return data if app.response.status == 400

        result = SecureBidding::Services::Projects::CreateMilestone.call(project: project, payload: data)
        if result[:ok]
          app.response.status = 201
          app.milestone_response(result[:milestone], policy: app.milestone_policy(result[:milestone]))
        else
          app.response.status = result[:status]
          { error: result[:error] }
        end
      end

      def self.award_project_bid(_req, app, id)
        unless app.valid_uuid?(id)
          app.response.status = 404
          return { error: 'Project not found' }
        end

        data = app.parse_json_request_body
        return data if app.response.status == 400

        bid_submission_id = data['bid_submission_id'] || data[:bid_submission_id]
        if bid_submission_id.to_s.strip.empty?
          app.response.status = 400
          return { error: 'bid_submission_id is required' }
        end

        result = SecureBidding::Services::Projects::AwardBid.call(
          project_id: id,
          bid_submission_id: bid_submission_id,
          auth_account: app.auth_account,
          awarded_bid_amount_cents: data['awarded_bid_amount_cents'] || data[:awarded_bid_amount_cents]
        )
        if result[:ok]
          { project_id: id, awarded_bid_submission_id: result[:awarded_bid_submission_id], state: 'in_progress' }
        else
          app.response.status = result[:status]
          { error: result[:error] }
        end
      end

      def self.request_project_payment(_req, app, id)
        lifecycle_action(id, app) do |project_id|
          SecureBidding::Services::Projects::RequestPayment.call(project_id: project_id, auth_account: app.auth_account)
        end
      end

      def self.process_project_payment(_req, app, id)
        lifecycle_action(id, app) do |project_id|
          SecureBidding::Services::Projects::ProcessPayment.call(
            project_id: project_id,
            auth_account: app.auth_account
          )
        end
      end

      def self.acknowledge_project_payment(_req, app, id)
        lifecycle_action(id, app) do |project_id|
          SecureBidding::Services::Projects::AcknowledgePayment.call(project_id: project_id, auth_account: app.auth_account)
        end
      end

      def self.lifecycle_action(id, app)
        unless app.valid_uuid?(id)
          app.response.status = 404
          return { error: 'Project not found' }
        end

        result = yield(id)
        if result[:ok]
          project = result[:project]
          {
            project_id: project.id,
            state: project.state,
            payment_status: project.payment_status,
            awarded_bid_submission_id: project.awarded_bid_submission_id,
            awarded_bid_amount_cents: project.awarded_bid_amount_cents,
            payment_amount_cents: project.payment_amount_cents
          }.compact
        else
          app.response.status = result[:status]
          { error: result[:error] }
        end
      end

      def self.list_project_bid_submissions(_req, app, id)
        unless app.valid_uuid?(id)
          app.response.status = 404
          return { error: 'Project not found' }
        end

        project = Project[id]
        if project && app.project_policy(project).view_bid_submissions?
          bid_submissions = project.bid_submissions_dataset.order(:id).all.map do |bid_submission|
            app.bid_submission_response(bid_submission, policy: app.bid_submission_policy(bid_submission))
          end
          { project_id: project.id, bid_submissions: bid_submissions }
        else
          app.response.status = 404
          { error: 'Project not found' }
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

        unless app.project_policy(project).update?
          app.response.status = 403
          return { error: 'Forbidden: only project owner or admin can update this project' }
        end

        update_data = app.parse_json_request_body
        return update_data if app.response.status == 400

        result = SecureBidding::Forms::ProjectsUpdateForm.new.call(update_data)
        validation_error = SecureBidding::FormValidation.response_for(app, result)
        return validation_error if validation_error

        if update_data.key?('state') && !Project::VALID_STATES.include?(update_data['state'])
          app.response.status = 400
          return { error: "state must be one of: #{Project::VALID_STATES.join(', ')}" }
        end

        if update_data.key?('budget_cents') && !update_data['budget_cents'].to_s.match?(/\A\d+\z/)
          app.response.status = 400
          return { error: 'budget_cents must be a non-negative integer' }
        end

        begin
          project.update(normalize_project_payload(update_data).transform_keys(&:to_sym))
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
          { error: 'Project not found' }
        elsif app.project_policy(project).destroy?
          project.delete
          { id: id, status: 'deleted' }
        else
          app.response.status = 403
          { error: 'Forbidden: only project owner or admin can delete this project' }
        end
      end

      def self.normalize_project_payload(data)
        normalized = data.dup
        if normalized.key?('required_documents')
          normalized['required_documents'] = Array(normalized['required_documents'])
                                             .map { |name| name.to_s.strip }
                                             .reject(&:empty?)
                                             .to_json
        end
        normalized
      end

      def self.admin?(app)
        auth = app.auth_account
        return false unless auth

        role = if auth.is_a?(Hash)
                 auth['system_role'] || auth[:system_role]
               else
                 auth.system_role
               end
        %w[admin system_admin].include?(role.to_s)
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
