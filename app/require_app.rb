# frozen_string_literal: true

require_relative 'db/database'

SecureBidding::Database.connect!
SecureBidding::Database.migrate!

require_relative 'models/bid'
require_relative 'models/project'
require_relative 'models/bid_submission'
require_relative 'models/password'
require_relative 'models/sso_identity'
require_relative 'models/google_account'
require_relative 'models/authorized_account'
require_relative 'models/account'
require_relative 'models/account_project'
require_relative 'models/role'
require_relative 'models/account_role'
require_relative 'models/project_membership'
require_relative 'models/payment'
require_relative 'models/milestone'
require_relative 'models/integrity_snapshot'
require_relative 'models/bid_document'
require_relative 'services/accounts/create_account'
require_relative 'services/accounts/get_account'
require_relative 'services/accounts/search_accounts'
require_relative 'services/accounts/update_account'
require_relative 'services/accounts/reset_accounts'
require_relative 'services/accounts/ensure_platform_admin'
require_relative 'services/email/send_verification'
require_relative 'services/auth/verification'
require_relative 'services/roles/ensure_roles'
require_relative 'services/roles/assign_system_role'
require_relative 'services/projects/create_project_requirement'
require_relative 'services/projects/assign_project_role'
require_relative 'services/projects/create_bid_for_project'
require_relative 'services/projects/generate_integrity_snapshot'
require_relative 'services/payments/create_payment'
require_relative 'services/payments/update_payment'
require_relative 'services/payments/fund_escrow'
require_relative 'services/payments/release_escrow'
require_relative 'services/projects/create_milestone'
require_relative 'services/projects/award_bid'
require_relative 'services/projects/request_payment'
require_relative 'services/projects/process_payment'
require_relative 'services/projects/acknowledge_payment'
require_relative 'services/authenticate_sso'
require_relative 'services/find_or_create_sso_account'
require_relative 'services/authorize_account'
require_relative 'lib/securable'
require_relative 'lib/secure_db'
require_relative 'lib/search_hash'
require_relative 'lib/key_stretching'
require_relative 'lib/auth_scope'
require_relative 'lib/oidc_verifier'
require_relative 'lib/google_id_token'
require_relative 'lib/auth_token'
require_relative 'lib/signed_request'
require_relative 'lib/client_ciphertext'
require_relative 'lib/form_validation'
require_relative 'lib/taipei_time'

require_relative 'forms/base_form'
require_relative 'policies/base_policy'

Dir[File.expand_path('forms/**/*.rb', __dir__)].sort.each do |file|
  next if file.end_with?('/base_form.rb')

  require file
end

Dir[File.expand_path('policies/**/*.rb', __dir__)].sort.each do |file|
  next if file.end_with?('/base_policy.rb')

  require file
end

auth_token_key = ENV['AUTH_TOKEN_KEY'].to_s
if auth_token_key.empty?
  if SecureBidding::Environment.app_env == 'production'
    raise KeyError, 'AUTH_TOKEN_KEY must be configured in production'
  end

  auth_token_key = SecureBidding::AuthToken.generate_key
end
SecureBidding::AuthToken.setup(auth_token_key)

SecureBidding::Environment.load_secrets!

verify_key = ENV['VERIFY_KEY'].to_s
signing_key = ENV['SIGNING_KEY'].to_s
if verify_key.empty?
  if SecureBidding::Environment.app_env == 'production'
    raise KeyError, 'VERIFY_KEY must be configured in production'
  end

  # Shared dev/test keypair — must match SIGNING_KEY in the web app secrets.
  verify_key = 'lH5S8eMKRq0QayFsiVomn8DKE1xTTOgdzoiMzjtES+c='
  signing_key = 'Q1QC/DUM0/UOmjYimkowLRDCkd+cvWXCeRfjOuUB8No=' if signing_key.empty?
end
SecureBidding::SignedRequest.setup(verify_key, signing_key.empty? ? nil : signing_key)

require_relative 'controllers/app'
