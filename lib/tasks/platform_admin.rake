# frozen_string_literal: true

namespace :accounts do
  desc 'Ensure scifiengineering (or PLATFORM_ADMIN_USERNAME) is the only platform admin'
  task :ensure_platform_admin, [:username] do |_task, args|
    require_relative '../../app/require_app'

    username = args[:username].presence || ENV.fetch('PLATFORM_ADMIN_USERNAME', 'scifiengineering')
    result = SecureBidding::Services::Accounts::EnsurePlatformAdmin.call(platform_admin_username: username)

    unless result[:ok]
      warn "ensure_platform_admin failed: #{result[:error]}"
      exit 1
    end

    puts "Platform admin: #{result[:platform_admin_username]} (#{result[:platform_admin_id]})"
    if result[:demoted_usernames].any?
      puts "Demoted former admins: #{result[:demoted_usernames].join(', ')}"
    else
      puts 'No other admin accounts needed demotion.'
    end
  end
end
