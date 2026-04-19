# frozen_string_literal: true

module SecureBidding
  module Environment
    module_function

    def app_env
      ENV.fetch('RACK_ENV', 'development')
    end

    def database_url
      ENV.fetch('DATABASE_URL', "sqlite://app/db/#{app_env}.db")
    end
  end
end
