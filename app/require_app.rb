# frozen_string_literal: true

require_relative 'db/database'

SecureBidding::Database.connect!
SecureBidding::Database.migrate!

require_relative 'models/bid'
require_relative 'models/account'
require_relative 'models/secret'
require_relative 'lib/secure_db'
require_relative 'controllers/app'
