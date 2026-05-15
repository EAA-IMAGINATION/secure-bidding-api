# frozen_string_literal: true

module SecureBidding
  module Routes
    module BidSubmissions
      def self.call(r, app)
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
            data = app.parse_json_request_body
            if app.response.status == 400
              data
            else
              payload = data
              project_id = payload['project_id']
              contractor_alias = payload['contractor_alias']
              plaintext_bid = payload['plaintext_bid']

              required_missing = [project_id, contractor_alias, plaintext_bid]
                                 .any? { |value| value.to_s.strip.empty? }
              if required_missing
                app.response.status = 400
                { error: 'project_id, contractor_alias, and plaintext_bid are required' }
              elsif !app.valid_uuid?(project_id)
                app.response.status = 400
                { error: 'project_id must be a UUID' }
              elsif Project[project_id].nil?
                app.response.status = 400
                { error: 'project_id does not reference an existing project' }
              else
                bid_submission = BidSubmission.new
                attributes = payload.reject { |key_name, _| key_name == 'plaintext_bid' }
                bid_submission.set(attributes.transform_keys(&:to_sym))
                bid_submission.encrypt_bid(plaintext_bid)
                bid_submission.save

                app.class::APP_LOGGER.info("bid_submission_created id=#{bid_submission.id}")
                app.response.status = 201
                { id: bid_submission.id, status: 'created' }
              end
            end
          rescue Sequel::MassAssignmentRestriction
            app.log_mass_assignment_attempt('bid_submission', payload, BidSubmission.allowed_columns + [:plaintext_bid])
            app.response.status = 400
            { error: 'Invalid bid submission attributes' }
          end

          # GET /api/v1/bid_submissions/:id - bid submission metadata only
          r.on String do |id|
            r.get do
              unless app.valid_uuid?(id)
                app.response.status = 404
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
                app.response.status = 404
                { error: 'Bid submission not found' }
              end
            end
          end
        end
      end
    end
  end
end
