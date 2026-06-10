# frozen_string_literal: true

require 'minitest/autorun'

describe 'Deployment files' do
  it 'defines the exact Heroku Procfile command' do
    procfile = File.read(File.expand_path('../Procfile', __dir__))
    expected = "release: bundle exec rake db:migrate_current\n" \
               "web: bundle exec puma -t 5:5 -p ${PORT:-3000} -e ${RACK_ENV:-development}\n"

    _(procfile).must_equal expected
  end
end
