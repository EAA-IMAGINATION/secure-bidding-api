# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require_relative '../app/require_app'

describe 'Milestone associations and deletion' do
  before do
    SecureBidding::Database.migrate!
    SecureBidding::Milestone.dataset.delete
    SecureBidding::Project.dataset.delete
  end

  it 'deletes milestones when project is deleted' do
    project = SecureBidding::Project.create(title: 'cascade-project', budget_cents: 1000)
    milestone = SecureBidding::Milestone.create(project_id: project.id, title: 'M1', budget_cents: 500)

    project.delete

    _(SecureBidding::Milestone.where(id: milestone.id).count).must_equal 0
  end
end
