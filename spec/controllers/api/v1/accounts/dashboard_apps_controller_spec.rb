require 'rails_helper'

RSpec.describe 'DashboardAppsController', type: :request do
  let(:account) { create(:account) }

  describe 'GET /api/v1/accounts/{account.id}/dashboard_apps' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/dashboard_apps"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:user) { create(:user, account: account) }
      let!(:dashboard_app) { create(:dashboard_app, user: user, account: account) }

      it 'returns all dashboard_apps in the account' do
        get "/api/v1/accounts/#{account.id}/dashboard_apps",
            headers: user.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        response_body = response.parsed_body
        expect(response_body.first['title']).to eq(dashboard_app.title)
        expect(response_body.first['content']).to eq(dashboard_app.content)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/dashboard_apps/:id' do
    let(:user) { create(:user, account: account) }
    let!(:dashboard_app) { create(:dashboard_app, user: user, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/dashboard_apps/#{dashboard_app.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'shows the dashboard app' do
        get "/api/v1/accounts/#{account.id}/dashboard_apps/#{dashboard_app.id}",
            headers: user.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.body).to include(dashboard_app.title)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/dashboard_apps' do
    let(:payload) { { dashboard_app: { title: 'CRM Dashboard', content: [{ type: 'frame', url: 'https://link.com' }] } } }
    let(:no_ssl_payload) { { dashboard_app: { title: 'CRM Dashboard', content: [{ type: 'frame', url: 'http://link.com' }] } } }
    let(:local_payload) { { dashboard_app: { title: 'Local Dashboard', content: [{ type: 'frame', url: 'http://localhost:3000/dashboard' }] } } }
    let(:invalid_type_payload) { { dashboard_app: { title: 'CRM Dashboard', content: [{ type: 'dda', url: 'https://link.com' }] } } }
    let(:invalid_url_payload) { { dashboard_app: { title: 'CRM Dashboard', content: [{ type: 'frame', url: 'com' }] } } }
    let(:non_http_url_payload) do
      { dashboard_app: { title: 'CRM Dashboard', content: [{ type: 'frame', url: 'ftp://wontwork.chatwoot.com/hello-world' }] } }
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        expect { post "/api/v1/accounts/#{account.id}/dashboard_apps", params: payload }.not_to change(CustomFilter, :count)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated administrator' do
      let(:user) { create(:user, account: account, role: :administrator) }

      it 'creates the dashboard app' do
        expect do
          post "/api/v1/accounts/#{account.id}/dashboard_apps", headers: user.create_new_auth_token,
                                                                params: payload
        end.to change(DashboardApp, :count).by(1)

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response['title']).to eq 'CRM Dashboard'
        expect(json_response['content'][0]['link']).to eq payload[:dashboard_app][:content][0][:link]
        expect(json_response['content'][0]['type']).to eq payload[:dashboard_app][:content][0][:type]
        expect(json_response['enabled']).to be(true)
      end

      it 'rejects remote dashboard apps without TLS' do
        expect do
          post "/api/v1/accounts/#{account.id}/dashboard_apps", headers: user.create_new_auth_token,
                                                                params: no_ssl_payload
        end.not_to change(DashboardApp, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'allows HTTP only for a local development host' do
        expect do
          post "/api/v1/accounts/#{account.id}/dashboard_apps", headers: user.create_new_auth_token,
                                                                params: local_payload
        end.to change(DashboardApp, :count).by(1)

        expect(response).to have_http_status(:success)
      end

      it 'does not create the dashboard app if invalid URL' do
        expect do
          post "/api/v1/accounts/#{account.id}/dashboard_apps", headers: user.create_new_auth_token,
                                                                params: invalid_url_payload
        end.not_to change(DashboardApp, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        json_response = response.parsed_body
        expect(json_response['message']).to include('Content : Invalid data')
      end

      it 'does not create the dashboard app if non HTTP URL' do
        expect do
          post "/api/v1/accounts/#{account.id}/dashboard_apps", headers: user.create_new_auth_token,
                                                                params: non_http_url_payload
        end.not_to change(DashboardApp, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        json_response = response.parsed_body
        expect(json_response['message']).to include('Content : Invalid data')
      end

      it 'rejects browser-executable and local-file URL schemes' do
        %w[javascript:alert(1) data:text/html,hello file:///tmp/app.html].each do |url|
          unsafe_payload = { dashboard_app: { title: 'Unsafe', content: [{ type: 'frame', url: url }] } }

          expect do
            post "/api/v1/accounts/#{account.id}/dashboard_apps", headers: user.create_new_auth_token,
                                                                  params: unsafe_payload
          end.not_to change(DashboardApp, :count)
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end

      it 'does not create the dashboard app if invalid type' do
        expect do
          post "/api/v1/accounts/#{account.id}/dashboard_apps", headers: user.create_new_auth_token,
                                                                params: invalid_type_payload
        end.not_to change(DashboardApp, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when it is an authenticated agent' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'does not create account-wide dashboard apps' do
        expect do
          post "/api/v1/accounts/#{account.id}/dashboard_apps",
               headers: agent.create_new_auth_token,
               params: payload,
               as: :json
        end.not_to change(DashboardApp, :count)

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/dashboard_apps/:id' do
    let(:payload) { { dashboard_app: { title: 'CRM Dashboard', content: [{ type: 'frame', url: 'https://link.com' }] } } }
    let(:user) { create(:user, account: account, role: :administrator) }
    let!(:dashboard_app) { create(:dashboard_app, user: user, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        put "/api/v1/accounts/#{account.id}/dashboard_apps/#{dashboard_app.id}",
            params: payload

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'updates the dashboard app' do
        patch "/api/v1/accounts/#{account.id}/dashboard_apps/#{dashboard_app.id}",
              headers: user.create_new_auth_token,
              params: payload,
              as: :json

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(dashboard_app.reload.title).to eq('CRM Dashboard')
        expect(json_response['content'][0]['link']).to eq payload[:dashboard_app][:content][0][:link]
        expect(json_response['content'][0]['type']).to eq payload[:dashboard_app][:content][0][:type]
      end

      it 'disables and re-enables the app without deleting it' do
        patch "/api/v1/accounts/#{account.id}/dashboard_apps/#{dashboard_app.id}",
              headers: user.create_new_auth_token,
              params: { dashboard_app: { enabled: false } },
              as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['enabled']).to be(false)
        expect(dashboard_app.reload.enabled).to be(false)

        patch "/api/v1/accounts/#{account.id}/dashboard_apps/#{dashboard_app.id}",
              headers: user.create_new_auth_token,
              params: { dashboard_app: { enabled: true } },
              as: :json

        expect(response.parsed_body['enabled']).to be(true)
        expect(dashboard_app.reload.enabled).to be(true)
      end

      it 'does not update an app from another account' do
        foreign_app = create(:dashboard_app)

        patch "/api/v1/accounts/#{account.id}/dashboard_apps/#{foreign_app.id}",
              headers: user.create_new_auth_token,
              params: payload,
              as: :json

        expect(response).to have_http_status(:not_found)
        expect(foreign_app.reload.title).not_to eq('CRM Dashboard')
      end
    end

    context 'when it is an authenticated agent' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'does not update account-wide dashboard apps' do
        patch "/api/v1/accounts/#{account.id}/dashboard_apps/#{dashboard_app.id}",
              headers: agent.create_new_auth_token,
              params: payload,
              as: :json

        expect(response).to have_http_status(:forbidden)
        expect(dashboard_app.reload.title).not_to eq('CRM Dashboard')
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/dashboard_apps/:id' do
    let(:user) { create(:user, account: account, role: :administrator) }
    let!(:dashboard_app) { create(:dashboard_app, user: user, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/dashboard_apps/#{dashboard_app.id}"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated admin user' do
      it 'deletes dashboard app' do
        delete "/api/v1/accounts/#{account.id}/dashboard_apps/#{dashboard_app.id}",
               headers: user.create_new_auth_token,
               as: :json
        expect(response).to have_http_status(:no_content)
        expect(user.dashboard_apps.count).to be 0
      end
    end

    context 'when it is an authenticated agent' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'does not delete account-wide dashboard apps' do
        delete "/api/v1/accounts/#{account.id}/dashboard_apps/#{dashboard_app.id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:forbidden)
        expect(DashboardApp.exists?(dashboard_app.id)).to be(true)
      end
    end
  end
end
