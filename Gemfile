# frozen_string_literal: true

source 'https://rubygems.org'

gem 'figaro'
gem 'json'
gem 'rackup'
gem 'rake'
gem 'rbnacl'
gem 'roda'
gem 'sequel'
gem 'sequel-seed'
gem 'sqlite3'

group :production do
  # Use pg in production for Heroku Postgres
  gem 'pg'
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
end
