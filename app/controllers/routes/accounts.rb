# frozen_string_literal: true

module SecureBidding
  module Routes
    # Handles accounts endpoints: listing, creation, searching and per-account actions.
    module Accounts
      def self.call(req, app)
        req.on 'accounts' do
          handle_accounts(req, app)
        end
      end

      def self.handle_accounts(req, app)
        register_accounts_collection(req, app)
        register_accounts_search(req, app)
        register_accounts_member_routes(req, app)
      end

      def self.register_accounts_collection(req, app)
        req.get true do
          list_accounts(req, app)
        end

        req.post true do
          create_account(req, app)
        end
      end

      def self.register_accounts_search(req, app)
        req.on 'search' do
          req.get true do
            search_accounts(req, app)
          end
        end
      end

      def self.register_accounts_member_routes(req, app)
        req.on String do |id|
          req.on 'system_roles' do
            req.get true do
              get_system_roles(req, app, id)
            end

            req.post true do
              assign_system_role(req, app, id)
            end
          end

          req.get true do
            get_account(req, app, id)
          end

          req.patch true do
            update_account(req, app, id)
          end
        end
      end

      def self.list_accounts(_req, _app)
        accounts = Account.order(:id).all.map do |account|
          { id: account.id, username: account.username, system_role: account.system_role }
        end
        { accounts: accounts }
      end

      def self.create_account(_req, app)
        data = app.parse_json_request_body
        return data if app.response.status == 400

        result = SecureBidding::Services::Accounts::CreateAccount.call(data)
        if result[:ok]
          app.response.status = 201
          { id: result[:account].id, status: 'created' }
        else
          app.response.status = result[:status]
          { error: result[:error] }
        end
      end

      def self.search_accounts(req, app)
        result = SecureBidding::Services::Accounts::SearchAccounts.call(
          email: req.params['email'],
          phone: req.params['phone']
        )
        if result[:ok]
          { accounts: result[:accounts].map { |account| app.account_response(account) } }
        else
          app.response.status = result[:status]
          { error: result[:error] }
        end
      end

      def self.get_system_roles(_req, app, id)
        unless app.valid_uuid?(id)
          app.response.status = 404
          return { error: 'Account not found' }
        end

        account = SecureBidding::Services::Accounts::GetAccount.call(id)
        if account
          { account_id: account.id, roles: account.system_roles_dataset.order(:name).select_map(:name) }
        else
          app.response.status = 404
          { error: 'Account not found' }
        end
      end

      def self.assign_system_role(_req, app, id)
        data = app.parse_json_request_body
        return data if app.response.status == 400

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

      def self.get_account(_req, app, id)
        unless app.valid_uuid?(id)
          app.response.status = 404
          { error: 'Account not found' }
        end

        account = SecureBidding::Services::Accounts::GetAccount.call(id)
        if account
          app.account_response(account)
        else
          app.response.status = 404
          { error: 'Account not found' }
        end
      end

      def self.update_account(_req, app, id)
        unless app.valid_uuid?(id)
          app.response.status = 404
          { error: 'Account not found' }
        end

        account = SecureBidding::Services::Accounts::GetAccount.call(id)
        if account.nil?
          app.response.status = 404
          { error: 'Account not found' }
        else
          data = app.parse_json_request_body
          return data if app.response.status == 400

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
