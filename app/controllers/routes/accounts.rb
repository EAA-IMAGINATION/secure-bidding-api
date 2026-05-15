# frozen_string_literal: true

module SecureBidding
  module Routes
    module Accounts
      def self.call(r, app)
        r.on 'accounts' do
          # GET /api/v1/accounts - list accounts (without secret fields)
          r.get true do
            accounts = Account.order(:id).all.map do |account|
              {
                id: account.id,
                username: account.username,
                system_role: account.system_role
              }
            end
            { accounts: accounts }
          end

          # POST /api/v1/accounts - create account with protected password/PII persistence
          r.post true do
            data = app.parse_json_request_body
            if app.response.status == 400
              data
            else
              result = SecureBidding::Services::Accounts::CreateAccount.call(data)
              if result[:ok]
                app.response.status = 201
                { id: result[:account].id, status: 'created' }
              else
                app.response.status = result[:status]
                { error: result[:error] }
              end
            end
          end

          # GET /api/v1/accounts/search?email=...&phone=...
          r.on 'search' do
            r.get true do
              result = SecureBidding::Services::Accounts::SearchAccounts.call(
                email: r.params['email'],
                phone: r.params['phone']
              )
              if result[:ok]
                { accounts: result[:accounts].map { |account| app.account_response(account) } }
              else
                app.response.status = result[:status]
                { error: result[:error] }
              end
            end
          end

          # GET/PATCH /api/v1/accounts/:id
          r.on String do |id|
            r.on 'system_roles' do
              r.get true do
                unless app.valid_uuid?(id)
                  app.response.status = 404
                  next { error: 'Account not found' }
                end

                account = SecureBidding::Services::Accounts::GetAccount.call(id)
                if account
                  { account_id: account.id, roles: account.system_roles_dataset.order(:name).select_map(:name) }
                else
                  app.response.status = 404
                  { error: 'Account not found' }
                end
              end

              r.post true do
                data = app.parse_json_request_body
                if app.response.status == 400
                  data
                else
                  result = SecureBidding::Services::Roles::AssignSystemRole.call(
                    account_id: id,
                    role_name: data['role']
                  )
                  if result[:ok]
                    app.response.status = 201
                    { account_id: id, role: result[:role], status: 'assigned' }
                  else
                    app.response.status = result[:status]
                    { error: result[:error] }
                  end
                end
              end
            end

            r.get true do
              unless app.valid_uuid?(id)
                app.response.status = 404
                next { error: 'Account not found' }
              end

              account = SecureBidding::Services::Accounts::GetAccount.call(id)
              if account
                app.account_response(account)
              else
                app.response.status = 404
                { error: 'Account not found' }
              end
            end

            r.patch true do
              unless app.valid_uuid?(id)
                app.response.status = 404
                next { error: 'Account not found' }
              end

              account = SecureBidding::Services::Accounts::GetAccount.call(id)
              if account.nil?
                app.response.status = 404
                { error: 'Account not found' }
              else
                data = app.parse_json_request_body
                if app.response.status == 400
                  data
                else
                  result = SecureBidding::Services::Accounts::UpdateAccount.call(account, data)
                  if result[:ok]
                    { id: result[:account].id, status: 'updated' }
                  else
                    app.response.status = result[:status]
                    { error: result[:error] }
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
