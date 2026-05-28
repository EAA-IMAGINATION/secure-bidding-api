# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require_relative '../app/require_app'

describe 'SecureBidding::Milestone' do
  before do
    SecureBidding::Database.migrate!
    SecureBidding::Milestone.dataset.delete
    SecureBidding::Project.dataset.delete
  end

  it 'can be created and belongs to a project' do
    project = SecureBidding::Project.create(title: 'pm-project', budget_cents: 50_000)
    milestone = SecureBidding::Milestone.create(project_id: project.id, title: 'Phase 1', budget_cents: 20_000)

    _(milestone.project.id).must_equal project.id
    _(project.milestones.map(&:id)).must_include milestone.id
  end
end
