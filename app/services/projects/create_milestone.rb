# frozen_string_literal: true

module SecureBidding
  module Services
    module Projects
      class CreateMilestone
        def self.call(project:, payload:)
          title = (payload['title'] || payload[:title]).to_s.strip
          budget_cents = payload['budget_cents'] || payload[:budget_cents]
          description = payload['description'] || payload[:description]
          sequence_order = payload['sequence_order'] || payload[:sequence_order]

          return { ok: false, status: 400, error: 'title is required' } if title.empty?
          return { ok: false, status: 400, error: 'budget_cents is required' } if budget_cents.to_s.strip.empty?
          return { ok: false, status: 400, error: 'budget_cents must be a non-negative integer' } unless budget_cents.to_s.match?(/\A\d+\z/)

          next_order = project.milestones_dataset.max(:sequence_order) || 0
          order = sequence_order.to_s.strip.empty? ? next_order + 1 : sequence_order.to_i

          milestone = SecureBidding::Milestone.create(
            project_id: project.id,
            title: title,
            description: description,
            budget_cents: budget_cents.to_i,
            state: 'pending_funding',
            sequence_order: order
          )

          { ok: true, milestone: milestone }
        rescue Sequel::ValidationFailed, Sequel::ConstraintViolation => e
          { ok: false, status: 400, error: e.message }
        end
      end
    end
  end
end
