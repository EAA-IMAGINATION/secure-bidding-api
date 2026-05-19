# frozen_string_literal: true

require_relative 'db/database'

SecureBidding::Database.connect!
SecureBidding::Database.migrate!

require_relative 'models/bid'
require_relative 'models/project'
require_relative 'models/bid_submission'
require_relative 'models/password'
require_relative 'models/account'
require_relative 'models/account_project'
require_relative 'models/role'
require_relative 'models/account_role'
require_relative 'models/project_membership'
require_relative 'models/payment'
require_relative 'services/accounts/create_account'
require_relative 'services/accounts/get_account'
require_relative 'services/accounts/search_accounts'
require_relative 'services/accounts/update_account'
require_relative 'services/accounts/reset_accounts'
require_relative 'services/email/send_verification'
require_relative 'services/roles/ensure_roles'
require_relative 'services/roles/assign_system_role'
require_relative 'services/projects/create_project_requirement'
require_relative 'services/projects/assign_project_role'
require_relative 'services/projects/create_bid_for_project'
require_relative 'services/payments/create_payment'
require_relative 'services/payments/update_payment'
require_relative 'lib/securable'
require_relative 'lib/secure_db'
require_relative 'lib/search_hash'
require_relative 'lib/key_stretching'
require_relative 'lib/auth_token'
require_relative 'lib/secure_messaging'
require_relative 'lib/registration_token'

# Initialize AuthToken with encryption key from environment
SecureBidding::AuthToken.setup(ENV.fetch('AUTH_TOKEN_KEY', nil))

require_relative 'controllers/app'
