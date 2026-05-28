namespace :db do
  desc 'Generate integrity snapshots for projects whose bidding_deadline has passed'
  task :generate_integrity_snapshots do
    require_relative '../../app/require_app'

    now = Time.now
    # Select projects whose bidding_deadline has passed
    projects = SecureBidding::Project.all.select do |p|
      p.bidding_deadline && p.bidding_deadline <= now
    end

    projects.each do |project|
      begin
        SecureBidding::Services::Projects::GenerateIntegritySnapshot.call(project)
        puts "Generated snapshot for project #{project.id}"
      rescue StandardError => e
        warn "Failed to generate snapshot for #{project.id}: #{e.class} - #{e.message}"
      end
    end
  end
end
