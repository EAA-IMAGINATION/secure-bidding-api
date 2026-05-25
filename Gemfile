# frozen_string_literal: true

source 'https://rubygems.org'

ruby '3.4.9'

gem 'logger'

gem 'base64'
gem 'figaro'
gem 'http', '~> 5.1'
gem 'json'
gem 'net-smtp'
gem 'rackup'
gem 'rake'
gem 'rbnacl'
gem 'roda'
gem 'sequel'
gem 'sequel-seed'
# HTTP client for outbound API calls
gem 'sqlite3'
gem 'dry-validation'

group :production do
  # Use pg in production for Heroku Postgres
  gem 'pg'
  gem 'puma'
end
gem 'webrick'

group :development do
  gem 'bundler-audit'
  gem 'hirb'
  gem 'pry'
  gem 'rubocop', require: false
end

group :test do
  gem 'minitest'
  gem 'rack-test'
  gem 'webmock' # Stub HTTP requests in tests
end
