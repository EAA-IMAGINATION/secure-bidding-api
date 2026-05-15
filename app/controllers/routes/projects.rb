# frozen_string_literal: true

module SecureBidding
  module Routes
    module Projects
      def self.call(r, app)
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
            data = app.parse_json_request_body
            if app.response.status == 400
              data
            elsif data.key?('owner_account_id')
              result = SecureBidding::Services::Projects::CreateProjectRequirement.call(data)
              if result[:ok]
                app.response.status = 201
                { id: result[:project].id, status: 'created' }
              else
                app.response.status = result[:status]
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
                app.response.status = 400
                { error: 'title and budget_cents are required' }
              elsif invalid_budget
                app.response.status = 400
                { error: 'budget_cents must be a non-negative integer' }
              else
                project.save
                app.class::APP_LOGGER.info("project_created id=#{project.id}")
                app.response.status = 201
                { id: project.id, status: 'created' }
              end
            end
          rescue Sequel::MassAssignmentRestriction
            app.log_mass_assignment_attempt('project', payload, Project.allowed_columns)
            app.response.status = 400
            { error: 'Invalid project attributes' }
          rescue Sequel::UniqueConstraintViolation
            app.response.status = 400
            { error: 'project title must be unique' }
          end

          # GET /api/v1/projects/:id - single project and nested routes
          r.on String do |id|
            r.on 'memberships' do
              r.get true do
                unless app.valid_uuid?(id)
                  app.response.status = 404
                  next { error: 'Project not found' }
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

              r.post true do
                unless app.valid_uuid?(id)
                  app.response.status = 404
                  next { error: 'Project not found' }
                end

                data = app.parse_json_request_body
                if app.response.status == 400
                  data
                else
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
              end
            end

            r.on 'bids' do
              r.post true do
                unless app.valid_uuid?(id)
                  app.response.status = 404
                  next { error: 'Project not found' }
                end

                data = app.parse_json_request_body
                if app.response.status == 400
                  data
                else
                  result = SecureBidding::Services::Projects::CreateBidForProject.call(
                    project_id: id,
                    payload: data
                  )
                  if result[:ok]
                    app.response.status = 201
                    { id: result[:bid_submission].id, status: 'created' }
                  else
                    app.response.status = result[:status]
                    { error: result[:error] }
                  end
                end
              end
            end

            r.get true do
              unless app.valid_uuid?(id)
                app.response.status = 404
                next { error: 'Project not found' }
              end

              project = Project[id]
              if project
                { id: project.id, title: project.title, budget_cents: project.budget_cents }
              else
                app.response.status = 404
                { error: 'Project not found' }
              end
            end

            r.on 'bid_submissions' do
              r.get true do
                unless app.valid_uuid?(id)
                  app.response.status = 404
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
                  app.response.status = 404
                  { error: 'Project not found' }
                end
              end
            end
          end
        end
      end
    end
  end
end
