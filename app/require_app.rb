# frozen_string_literal: true

require_relative 'db/database'

SecureBidding::Database.connect!
SecureBidding::Database.migrate!

require_relative 'models/bid'
require_relative 'models/project'
require_relative 'models/bid_submission'
require_relative 'lib/secure_db'
require_relative 'controllers/app'
