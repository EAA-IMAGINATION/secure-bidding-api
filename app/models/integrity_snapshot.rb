# frozen_string_literal: true

module SecureBidding
  # Represents the canonical integrity snapshot taken at a project's bidding deadline.
  class IntegritySnapshot < Sequel::Model(:integrity_snapshots)
    plugin :uuid, field: :id
    plugin :whitelist_security

    many_to_one :project, class: 'SecureBidding::Project', key: :project_id

    set_allowed_columns :project_id, :canonical_hash, :snapshot_taken_at
  end
end
