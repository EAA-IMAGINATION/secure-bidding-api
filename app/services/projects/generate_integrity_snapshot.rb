# frozen_string_literal: true

require 'digest'

module SecureBidding
  module Services
    module Projects
      # Generates the canonical integrity snapshot for a project at deadline.
      class GenerateIntegritySnapshot
        def self.call(project)
          # Collect per-bidhash: combine secure_encrypted_bid and any bid document hashes
          bid_hashes = project.bid_submissions.map do |bs|
            parts = []
            parts << bs.secure_encrypted_bid.to_s
            # include bid document hashes if present
            if bs.respond_to?(:bid_documents)
              doc_hashes = bs.bid_documents.map { |d| d.file_hash.to_s }.sort
              parts.concat(doc_hashes)
            end
            Digest::SHA256.hexdigest(parts.join)
          end

          canonical = Digest::SHA256.hexdigest(bid_hashes.sort.join)

          # Upsert snapshot (uniqueness on project_id expected)
          snapshot = SecureBidding::IntegritySnapshot.where(project_id: project.id).first
          if snapshot
            snapshot.update(canonical_hash: canonical, snapshot_taken_at: Time.now)
          else
            SecureBidding::IntegritySnapshot.create(project_id: project.id, canonical_hash: canonical, snapshot_taken_at: Time.now)
          end
        end
      end
    end
  end
end
