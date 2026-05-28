# frozen_string_literal: true

module SecureBidding
  # Represents a milestone within a project.
  class Milestone < Sequel::Model(:milestones)
    plugin :uuid, field: :id
    plugin :whitelist_security
    plugin :association_dependencies

    set_allowed_columns :project_id, :title, :description, :budget_cents, :assigned_bidder_id, :state, :sequence_order

    many_to_one :project, class: 'SecureBidding::Project', key: :project_id
    one_to_many :payments, class: 'SecureBidding::Payment', key: :milestone_id

    add_association_dependencies payments: :delete
  end
end
