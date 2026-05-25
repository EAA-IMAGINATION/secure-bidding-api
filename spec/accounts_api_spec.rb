# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'json'
require 'cgi'
require_relative '../app/require_app'

# rubocop:disable Metrics/BlockLength
describe 'API /api/v1/accounts' do
  include Rack::Test::Methods

  def app
    SecureBidding::App.freeze.app
  end

  before do
    SecureBidding::AuthToken.setup(SecureBidding::AuthToken.generate_key)
    SecureBidding::Database.migrate!
    SecureBidding::BidSubmission.dataset.delete
    SecureBidding::Project.dataset.delete
    SecureBidding::AccountProject.dataset.delete
    SecureBidding::Account.dataset.delete
  end

  it 'HAPPY: creates an account with POST /api/v1/accounts' do
    payload = {
      username: 'route-alice',
      password: 'my-secret-pass',
      email: 'route-alice@example.com',
      phone: '+886900000001',
      system_role: 'member'
    }

    post '/api/v1/accounts', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 201
    response_body = JSON.parse(last_response.body)
    _(response_body['id']).wont_be_nil
    _(response_body['status']).must_equal 'created'

    stored = SecureBidding::Account[response_body['id']]
    _(stored).wont_be_nil
    _(stored.password_hash).wont_equal payload[:password]
  end

  it 'HAPPY: gets account metadata with GET /api/v1/accounts/:id' do
    account = SecureBidding::Account.new(username: 'route-bob', system_role: 'admin')
    account.set_password('my-secret-pass')
    account.set_email('route-bob@example.com')
    account.set_phone('+886900000002')
    account.save

    get "/api/v1/accounts/#{account.id}"

    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['id']).must_equal account.id
    _(response_body['username']).must_equal 'route-bob'
    _(response_body['system_role']).must_equal 'admin'
    _(response_body['email']).must_equal 'route-bob@example.com'
    _(response_body['phone']).must_equal '+886900000002'
    _(response_body.key?('password_hash')).must_equal false
    _(response_body.key?('password_salt')).must_equal false
    _(response_body.key?('email_secure')).must_equal false
  end

  it 'HAPPY: lists accounts with GET /api/v1/accounts when admin' do
    admin = SecureBidding::Account.new(username: 'list-admin', system_role: 'admin')
    admin.set_password('my-secret-pass')
    admin.set_email('list-admin@example.com')
    admin.save

    account = SecureBidding::Account.new(username: 'list-user', system_role: 'member')
    account.set_password('my-secret-pass')
    account.set_email('list-user@example.com')
    account.save

    token = SecureBidding::AuthToken.tokenize(
      { account_id: admin.id, username: admin.username, system_role: admin.system_role },
      SecureBidding::AuthToken::ONE_HOUR
    )
    headers = { 'HTTP_AUTHORIZATION' => "Bearer #{token}" }

    get '/api/v1/accounts', '', headers

    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['accounts']).must_be_kind_of Array
    _(response_body['accounts'].length).must_equal 2
  end

  it 'HAPPY: searches accounts by email on GET /api/v1/accounts/search' do
    account = SecureBidding::Account.new(username: 'search-email-user', system_role: 'member')
    account.set_password('my-secret-pass')
    account.set_email('search-email@example.com')
    account.save

    get "/api/v1/accounts/search?email=#{CGI.escape('search-email@example.com')}"

    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['accounts']).must_be_kind_of Array
    _(response_body['accounts'].length).must_equal 1
    _(response_body['accounts'][0]['id']).must_equal account.id
    _(response_body['accounts'][0]['username']).must_equal 'search-email-user'
  end

  it 'SAD: rejects account creation with missing required fields' do
    post '/api/v1/accounts',
         { username: 'missing-password' }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'username, password, and email are required'
  end

  it 'SAD: rejects account creation with invalid system_role' do
    payload = {
      username: 'bad-role-user',
      password: 'my-secret-pass',
      email: 'bad-role@example.com',
      system_role: 'super-admin'
    }

    post '/api/v1/accounts', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'system_role must be admin or member'
  end

  it 'SAD: returns 404 for missing account id' do
    get '/api/v1/accounts/00000000-0000-0000-0000-000000000000'

    _(last_response.status).must_equal 404
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'Account not found'
  end

  it 'SAD: rejects search without email or phone criteria' do
    get '/api/v1/accounts/search'

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'email or phone query parameter is required'
  end

  it 'HAPPY: updates account fields with PATCH /api/v1/accounts/:id when admin' do
    admin = SecureBidding::Account.new(username: 'patch-admin', system_role: 'admin')
    admin.set_password('my-secret-pass')
    admin.set_email('patch-admin@example.com')
    admin.save

    account = SecureBidding::Account.new(username: 'updatable-user', system_role: 'member')
    account.set_password('my-secret-pass')
    account.set_email('updatable-user@example.com')
    account.save

    token = SecureBidding::AuthToken.tokenize(
      { account_id: admin.id, username: admin.username, system_role: admin.system_role },
      SecureBidding::AuthToken::ONE_HOUR
    )
    headers = { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }

    patch "/api/v1/accounts/#{account.id}",
          { phone: '+886911222333', system_role: 'admin' }.to_json,
          headers

    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['id']).must_equal account.id
    _(response_body['status']).must_equal 'updated'

    updated = SecureBidding::Account[account.id]
    _(updated.system_role).must_equal 'admin'
    _(updated.phone).must_equal '+886911222333'
  end

  it 'HAPPY: member can update own username email and password' do
    account = SecureBidding::Account.new(username: 'self-update-user', system_role: 'member')
    account.set_password('old-secret-pass')
    account.set_email('self-update-user@example.com')
    account.save

    token = SecureBidding::AuthToken.tokenize(
      { account_id: account.id, username: account.username, system_role: account.system_role },
      SecureBidding::AuthToken::ONE_HOUR
    )
    headers = { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }

    patch "/api/v1/accounts/#{account.id}",
          {
            username: 'self-update-user-renamed',
            email: 'self-update-user-renamed@example.com',
            password: 'new-secret-pass'
          }.to_json,
          headers

    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['status']).must_equal 'updated'

    updated = SecureBidding::Account[account.id]
    _(updated.username).must_equal 'self-update-user-renamed'
    _(updated.email).must_equal 'self-update-user-renamed@example.com'
    _(updated.check_password('new-secret-pass')).must_equal true
    _(updated.check_password('old-secret-pass')).must_equal false
  end

  it 'SAD: member cannot promote self with account update' do
    account = SecureBidding::Account.new(username: 'self-escalation-user', system_role: 'member')
    account.set_password('my-secret-pass')
    account.set_email('self-escalation-user@example.com')
    account.save

    token = SecureBidding::AuthToken.tokenize(
      { account_id: account.id, username: account.username, system_role: account.system_role },
      SecureBidding::AuthToken::ONE_HOUR
    )
    headers = { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }

    patch "/api/v1/accounts/#{account.id}",
          { system_role: 'admin' }.to_json,
          headers

    _(last_response.status).must_equal 403
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'Forbidden: account owner cannot change system role'
    _(SecureBidding::Account[account.id].system_role).must_equal 'member'
  end

  it 'SAD: rejects account update without updatable fields' do
    admin = SecureBidding::Account.new(username: 'no-update-admin', system_role: 'admin')
    admin.set_password('my-secret-pass')
    admin.set_email('no-update-admin@example.com')
    admin.save

    account = SecureBidding::Account.new(username: 'no-update-user', system_role: 'member')
    account.set_password('my-secret-pass')
    account.set_email('no-update-user@example.com')
    account.save

    token = SecureBidding::AuthToken.tokenize(
      { account_id: admin.id, username: admin.username, system_role: admin.system_role },
      SecureBidding::AuthToken::ONE_HOUR
    )
    headers = { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }

    patch "/api/v1/accounts/#{account.id}", {}.to_json, headers

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'At least one updatable field is required'
  end

  it 'SAD: blocks mass assignment keys for account creation' do
    payload = {
      id: 'forced-id',
      username: 'forced-id-user',
      password: 'my-secret-pass',
      email: 'forced-id@example.com',
      system_role: 'member'
    }

    post '/api/v1/accounts', payload.to_json, { 'CONTENT_TYPE' => 'application/json' }

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'Invalid account attributes'
  end

  it 'HAPPY: admin can delete an account with DELETE /api/v1/accounts/:id' do
    admin = SecureBidding::Account.new(username: 'delete-admin', system_role: 'admin')
    admin.set_password('my-secret-pass')
    admin.set_email('delete-admin@example.com')
    admin.save

    target = SecureBidding::Account.new(username: 'delete-target', system_role: 'member')
    target.set_password('my-secret-pass')
    target.set_email('delete-target@example.com')
    target.save

    token = SecureBidding::AuthToken.tokenize(
      { account_id: admin.id, username: admin.username, system_role: admin.system_role },
      SecureBidding::AuthToken::ONE_HOUR
    )
    headers = { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }

    delete "/api/v1/accounts/#{target.id}", '', headers

    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['id']).must_equal target.id
    _(response_body['status']).must_equal 'deleted'
    _(SecureBidding::Account[target.id]).must_be_nil
  end

  it 'SAD: non-admin cannot delete an account' do
    member = SecureBidding::Account.new(username: 'delete-member', system_role: 'member')
    member.set_password('my-secret-pass')
    member.set_email('delete-member@example.com')
    member.save

    target = SecureBidding::Account.new(username: 'delete-target2', system_role: 'member')
    target.set_password('my-secret-pass')
    target.set_email('delete-target2@example.com')
    target.save

    token = SecureBidding::AuthToken.tokenize(
      { account_id: member.id, username: member.username, system_role: member.system_role },
      SecureBidding::AuthToken::ONE_HOUR
    )
    headers = { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }

    delete "/api/v1/accounts/#{target.id}", '', headers

    _(last_response.status).must_equal 403
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).wont_be_nil
    _(SecureBidding::Account[target.id]).wont_be_nil
  end

  it 'SAD: non-admin cannot update an account' do
    member = SecureBidding::Account.new(username: 'update-member', system_role: 'member')
    member.set_password('my-secret-pass')
    member.set_email('update-member@example.com')
    member.save

    target = SecureBidding::Account.new(username: 'update-target', system_role: 'member')
    target.set_password('my-secret-pass')
    target.set_email('update-target@example.com')
    target.save

    token = SecureBidding::AuthToken.tokenize(
      { account_id: member.id, username: member.username, system_role: member.system_role },
      SecureBidding::AuthToken::ONE_HOUR
    )
    headers = { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }

    patch "/api/v1/accounts/#{target.id}",
          { phone: '+886999999999' }.to_json,
          headers

    _(last_response.status).must_equal 403
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).wont_be_nil
  end

  it 'SAD: non-admin cannot list all accounts' do
    member = SecureBidding::Account.new(username: 'list-member', system_role: 'member')
    member.set_password('my-secret-pass')
    member.set_email('list-member@example.com')
    member.save

    token = SecureBidding::AuthToken.tokenize(
      { account_id: member.id, username: member.username, system_role: member.system_role },
      SecureBidding::AuthToken::ONE_HOUR
    )
    headers = { 'HTTP_AUTHORIZATION' => "Bearer #{token}" }

    get '/api/v1/accounts', '', headers

    _(last_response.status).must_equal 403
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).wont_be_nil
  end

  it 'SAD: non-admin cannot assign system roles' do
    member = SecureBidding::Account.new(username: 'assign-member', system_role: 'member')
    member.set_password('my-secret-pass')
    member.set_email('assign-member@example.com')
    member.save

    target = SecureBidding::Account.new(username: 'assign-target', system_role: 'member')
    target.set_password('my-secret-pass')
    target.set_email('assign-target@example.com')
    target.save

    token = SecureBidding::AuthToken.tokenize(
      { account_id: member.id, username: member.username, system_role: member.system_role },
      SecureBidding::AuthToken::ONE_HOUR
    )
    headers = { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }

    post "/api/v1/accounts/#{target.id}/system_roles",
         { role: 'admin' }.to_json,
         headers

    _(last_response.status).must_equal 403
  end

  it 'HAPPY: admin can promote a member to admin with system_roles endpoint' do
    admin = SecureBidding::Account.new(username: 'promote-admin', system_role: 'admin')
    admin.set_password('my-secret-pass')
    admin.set_email('promote-admin@example.com')
    admin.save

    target = SecureBidding::Account.new(username: 'promote-target', system_role: 'member')
    target.set_password('my-secret-pass')
    target.set_email('promote-target@example.com')
    target.save

    token = SecureBidding::AuthToken.tokenize(
      { account_id: admin.id, username: admin.username, system_role: admin.system_role },
      SecureBidding::AuthToken::ONE_HOUR
    )
    headers = { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }

    post "/api/v1/accounts/#{target.id}/system_roles",
         { role: 'admin' }.to_json,
         headers

    _(last_response.status).must_equal 201
    response_body = JSON.parse(last_response.body)
    _(response_body['status']).must_equal 'assigned'

    promoted = SecureBidding::Account[target.id]
    _(promoted.system_role).must_equal 'admin'
  end
end
# rubocop:enable Metrics/BlockLength
