# frozen_string_literal: true

require 'json'

module SecureBidding
  module Services
    module Projects
      # Creates a bid submission for a project if bidder membership is present.
      class CreateBidForProject
        UUID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/.freeze

        def self.call(project_id:, payload:, auth_account:)
          project = SecureBidding::Project[project_id]
          return { ok: false, status: 404, error: 'Project not found' } if project.nil?
          return { ok: false, status: 403, error: 'Project is not open for bidding' } unless project.state == 'published'
          if SecureBidding::Policies::ProjectPolicy.bidding_closed_for?(project)
            return { ok: false, status: 403, error: 'Bidding deadline has passed' }
          end
          return { ok: false, status: 403, error: 'Login required to bid on projects' } if auth_account.nil?

          bidder_account_id = payload['bidder_account_id']
          contractor_alias = payload['contractor_alias']
          encrypted_bid_amount = payload['encrypted_bid_amount']
          encrypted_proposal_text = payload['encrypted_proposal_text']
          encrypted_document = payload['encrypted_document']
          document_file_name = payload['document_file_name']
          document_file_hash = payload['document_file_hash']
          required_documents = parse_required_documents(project)

          if [bidder_account_id, contractor_alias, encrypted_bid_amount, encrypted_proposal_text].any? { |value| value.to_s.strip.empty? }
            return { ok: false, status: 400,
                     error: 'bidder_account_id, contractor_alias, encrypted_bid_amount, and encrypted_proposal_text are required' }
          elsif !uuid?(bidder_account_id)
            return { ok: false, status: 400, error: 'bidder_account_id must be a UUID' }
          elsif !ClientCiphertext.valid_envelope?(encrypted_bid_amount) || !ClientCiphertext.valid_envelope?(encrypted_proposal_text)
            return { ok: false, status: 400, error: 'encrypted bid payloads must be valid NaCl envelopes' }
          elsif required_documents.any? && !ClientCiphertext.valid_envelope?(encrypted_document)
            return { ok: false, status: 400, error: 'All required documents must be uploaded before submitting a bid' }
          elsif required_documents.any? && !required_documents_satisfied?(required_documents, document_file_hash)
            return { ok: false, status: 400, error: 'All required documents must be uploaded before submitting a bid' }
          end

          bidder = SecureBidding::Account[bidder_account_id]
          if bidder.nil?
            return { ok: false, status: 400,
                     error: 'bidder_account_id must reference an existing account' }
          end

          auth_account_id = auth_account[:account_id] || auth_account['account_id']
          return { ok: false, status: 403, error: 'Not authorized to bid for this account' } if auth_account_id != bidder.id
          return { ok: false, status: 403, error: 'Project owner cannot bid on own project' } if owner_of_project?(project.id, bidder.id)

          bid_submission = SecureBidding::BidSubmission.new(
            project_id: project.id,
            contractor_alias: contractor_alias,
            bidder_account_id: bidder.id
          )
          bid_submission.store_client_ciphertext(encrypted_bid_amount, encrypted_proposal_text)
          if encrypted_document && !encrypted_document.to_s.strip.empty?
            bid_submission.encrypted_document = ClientCiphertext.normalize_envelope(encrypted_document)
            bid_submission.document_file_name = document_file_name.to_s.strip
            bid_submission.document_file_hash = document_file_hash.to_s.strip
          end
          bid_submission.save
          { ok: true, bid_submission: bid_submission }
        end

        def self.owner_of_project?(project_id, account_id)
          owner_role = SecureBidding::Role.ensure_role('project_owner')
          owner_membership = SecureBidding::ProjectMembership.first(
            account_id: account_id,
            project_id: project_id,
            role_id: owner_role.id
          )
          return true unless owner_membership.nil?

          collaboration = SecureBidding::AccountProject.first(
            account_id: account_id,
            project_id: project_id
          )
          !collaboration.nil? && collaboration.collaboration_role == 'owner'
        end

        def self.uuid?(value)
          value.to_s.match?(UUID_FORMAT)
        end

        def self.parse_required_documents(project)
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
      end
    end
  end
end
