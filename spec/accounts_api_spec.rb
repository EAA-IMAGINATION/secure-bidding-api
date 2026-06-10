# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'json'
require 'cgi'
require_relative 'spec_helper'

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

  it 'SAD: rejects direct account creation with POST /api/v1/accounts' do
    payload = {
      username: 'route-alice',
      password: 'my-secret-pass',
      email: 'route-alice@example.com',
      phone: '+886900000001',
      system_role: 'member'
    }

    signed_post '/api/v1/accounts', payload

    _(last_response.status).must_equal 405
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_include 'auth/register'
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
    _(response_body['profile_roles']).must_equal %w[admin]
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
    _(response_body['accounts'].length).must_equal 1
    _(response_body['accounts'].map { |row| row['id'] }).wont_include admin.id
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
    signed_post '/api/v1/accounts',
                { username: 'missing-password' }

    _(last_response.status).must_equal 405
  end

  it 'SAD: rejects account creation with invalid system_role' do
    payload = {
      username: 'bad-role-user',
      password: 'my-secret-pass',
      email: 'bad-role@example.com',
      system_role: 'super-admin'
    }

    signed_post '/api/v1/accounts', payload

    _(last_response.status).must_equal 405
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

  it 'HAPPY: updates own account fields with PATCH /api/v1/accounts/:id' do
    account = SecureBidding::Account.new(username: 'updatable-user', system_role: 'member')
    account.set_password('my-secret-pass')
    account.set_email('updatable-user@example.com')
    account.save

    token = SecureBidding::AuthToken.tokenize(
      { account_id: account.id, username: account.username, system_role: account.system_role },
      SecureBidding::AuthToken::ONE_HOUR
    )
    headers = { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }

    patch "/api/v1/accounts/#{account.id}",
          { phone: '+886911222333' }.to_json,
          headers

    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['id']).must_equal account.id
    _(response_body['status']).must_equal 'updated'

    updated = SecureBidding::Account[account.id]
    _(updated.system_role).must_equal 'member'
    _(updated.phone).must_equal '+886911222333'
  end

  it 'SAD: admin cannot update another member account profile' do
    admin = SecureBidding::Account.new(username: 'patch-admin', system_role: 'admin')
    admin.set_password('my-secret-pass')
    admin.set_email('patch-admin@example.com')
    admin.save

    account = SecureBidding::Account.new(username: 'locked-user', system_role: 'member')
    account.set_password('my-secret-pass')
    account.set_email('locked-user@example.com')
    account.save

    token = SecureBidding::AuthToken.tokenize(
      { account_id: admin.id, username: admin.username, system_role: admin.system_role },
      SecureBidding::AuthToken::ONE_HOUR
    )
    headers = { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }

    patch "/api/v1/accounts/#{account.id}",
          { phone: '+886911222333' }.to_json,
          headers

    _(last_response.status).must_equal 403
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
    account = SecureBidding::Account.new(username: 'no-update-user', system_role: 'member')
    account.set_password('my-secret-pass')
    account.set_email('no-update-user@example.com')
    account.save

    token = SecureBidding::AuthToken.tokenize(
      { account_id: account.id, username: account.username, system_role: account.system_role },
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

    signed_post '/api/v1/accounts', payload

    _(last_response.status).must_equal 405
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

  it 'SAD: rejects capability roles via system_roles endpoint' do
    admin = SecureBidding::Account.new(username: 'cap-admin', system_role: 'admin')
    admin.set_password('my-secret-pass')
    admin.set_email('cap-admin@example.com')
    admin.save

    target = SecureBidding::Account.new(username: 'cap-target', system_role: 'member')
    target.set_password('my-secret-pass')
    target.set_email('cap-target@example.com')
    target.save

    token = SecureBidding::AuthToken.tokenize(
      { account_id: admin.id, username: admin.username, system_role: admin.system_role },
      SecureBidding::AuthToken::ONE_HOUR
    )
    headers = { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }

    post "/api/v1/accounts/#{target.id}/system_roles",
         { role: 'project_owner' }.to_json,
         headers

    _(last_response.status).must_equal 400
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_include 'admin or member'
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

  it 'SAD: admin cannot change their own role with system_roles endpoint' do
    admin = SecureBidding::Account.new(username: 'self-role-admin', system_role: 'admin')
    admin.set_password('my-secret-pass')
    admin.set_email('self-role-admin@example.com')
    admin.save

    token = SecureBidding::AuthToken.tokenize(
      { account_id: admin.id, username: admin.username, system_role: admin.system_role },
      SecureBidding::AuthToken::ONE_HOUR
    )
    headers = { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }

    post "/api/v1/accounts/#{admin.id}/system_roles",
         { role: 'member' }.to_json,
         headers

    _(last_response.status).must_equal 403
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'Forbidden: admins cannot change their own account role'
    _(SecureBidding::Account[admin.id].system_role).must_equal 'admin'
  end

  it 'SAD: admin cannot change their own role with account update' do
    admin = SecureBidding::Account.new(username: 'self-patch-admin', system_role: 'admin')
    admin.set_password('my-secret-pass')
    admin.set_email('self-patch-admin@example.com')
    admin.save

    token = SecureBidding::AuthToken.tokenize(
      { account_id: admin.id, username: admin.username, system_role: admin.system_role },
      SecureBidding::AuthToken::ONE_HOUR
    )
    headers = { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }

    patch "/api/v1/accounts/#{admin.id}",
          { system_role: 'member' }.to_json,
          headers

    _(last_response.status).must_equal 403
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'Forbidden: admins cannot change their own account role'
    _(SecureBidding::Account[admin.id].system_role).must_equal 'admin'
  end

  it 'HAPPY: account owner can POST /api/v1/accounts/:id/resend_verification' do
    account = SecureBidding::Account.new(username: 'resend-owner', system_role: 'member')
    account.set_password('my-secret-pass')
    account.set_email('resend-owner@example.com')
    account.save

    token = SecureBidding::AuthToken.tokenize(
      { account_id: account.id, username: account.username, system_role: account.system_role },
      SecureBidding::AuthToken::ONE_HOUR
    )
    headers = { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }

    # Stub email sending to avoid SMTP in tests
    original = SecureBidding::Services::Email::SendVerification.method(:call)
    SecureBidding::Services::Email::SendVerification.define_singleton_method(:call) do |account:, verification_link:, purpose: :registration|
      { ok: true, message: 'stubbed' }
    end

    begin
      post "/api/v1/accounts/#{account.id}/resend_verification", '', headers

      _(last_response.status).must_equal 200
      response_body = JSON.parse(last_response.body)
      _(response_body['id']).must_equal account.id
      _(response_body['status']).must_equal 'verification_sent'

      refreshed = SecureBidding::Account[account.id]
      _(refreshed.registration_token).wont_be_nil
      _(refreshed.registration_token_expires_at).wont_be_nil
    ensure
      SecureBidding::Services::Email::SendVerification.define_singleton_method(:call, original)
    end
  end

  it 'SAD: non-admin non-owner cannot POST resend_verification' do
    owner = SecureBidding::Account.new(username: 'resend-owner2', system_role: 'member')
    owner.set_password('my-secret-pass')
    owner.set_email('resend-owner2@example.com')
    owner.save

    attacker = SecureBidding::Account.new(username: 'attacker', system_role: 'member')
    attacker.set_password('my-secret-pass')
    attacker.set_email('attacker@example.com')
    attacker.save

    token = SecureBidding::AuthToken.tokenize(
      { account_id: attacker.id, username: attacker.username, system_role: attacker.system_role },
      SecureBidding::AuthToken::ONE_HOUR
    )
    headers = { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }

    post "/api/v1/accounts/#{owner.id}/resend_verification", '', headers

    _(last_response.status).must_equal 403
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_include 'Forbidden'
  end

  it 'SAD: returns 502 when email sending fails' do
    account = SecureBidding::Account.new(username: 'resend-owner3', system_role: 'member')
    account.set_password('my-secret-pass')
    account.set_email('resend-owner3@example.com')
    account.save

    token = SecureBidding::AuthToken.tokenize(
      { account_id: account.id, username: account.username, system_role: account.system_role },
      SecureBidding::AuthToken::ONE_HOUR
    )
    headers = { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }

    original = SecureBidding::Services::Email::SendVerification.method(:call)
    SecureBidding::Services::Email::SendVerification.define_singleton_method(:call) do |account:, verification_link:, purpose: :registration|
      raise SecureBidding::Services::Email::SendVerification::MailerToGoError, 'SMTP failed'
    end

    begin
      post "/api/v1/accounts/#{account.id}/resend_verification", '', headers

      _(last_response.status).must_equal 502
      response_body = JSON.parse(last_response.body)
      _(response_body['error']).must_include 'Failed to send'
    ensure
      SecureBidding::Services::Email::SendVerification.define_singleton_method(:call, original)
    end
  end

  it 'SAD: resend_verification rejects already verified accounts' do
    account = SecureBidding::Account.new(username: 'verified-resend', system_role: 'member')
    account.set_password('my-secret-pass')
    account.set_email('verified-resend@example.com')
    account.verify_email!
    account.save

    token = SecureBidding::AuthToken.tokenize(
      { account_id: account.id, username: account.username, system_role: account.system_role },
      SecureBidding::AuthToken::ONE_HOUR
    )
    headers = { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }

    post "/api/v1/accounts/#{account.id}/resend_verification", '', headers

    _(last_response.status).must_equal 422
    response_body = JSON.parse(last_response.body)
    _(response_body['error']).must_equal 'Email is already verified'
  end

  it 'HAPPY: returns stacked profile_roles for GET /api/v1/accounts/:username' do
    owner = SecureBidding::Account.new(username: 'profile-owner', system_role: 'member')
    owner.set_password('my-secret-pass')
    owner.set_email('profile-owner@example.com')
    owner.verify_email!
    owner.save

    project = SecureBidding::Project.create(title: 'profile-owner-project', budget_cents: 50_000, state: 'published')
    owner_role = SecureBidding::Role.ensure_role('project_owner')
    SecureBidding::ProjectMembership.create(account_id: owner.id, project_id: project.id, role_id: owner_role.id)

    token = SecureBidding::AuthToken.tokenize(
      { account_id: owner.id, username: owner.username, system_role: owner.system_role },
      SecureBidding::AuthToken::ONE_HOUR
    )
    headers = { 'HTTP_AUTHORIZATION' => "Bearer #{token}" }

    get "/api/v1/accounts/#{owner.username}", {}, headers

    _(last_response.status).must_equal 200
    response_body = JSON.parse(last_response.body)
    _(response_body['profile_roles']).must_equal %w[member project_owner]
    _(response_body.key?('api_key')).must_equal true
  end

  it 'SAD: does not expose admin user creation routes' do
    get '/api/v1/admin/users/new'
    _(last_response.status).must_equal 404

    post '/api/v1/admin/users', { username: 'someone', email: 'someone@example.com' }.to_json,
         'CONTENT_TYPE' => 'application/json'
    _(last_response.status).must_equal 404
  end
end
# rubocop:enable Metrics/BlockLength
