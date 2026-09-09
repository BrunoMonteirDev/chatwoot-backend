require 'rails_helper'

RSpec.describe 'Label API', type: :request do
  let!(:account) { create(:account) }
  let!(:label) { create(:label, account: account) }
  let!(:conversation) { create(:conversation, account: account) }

  describe 'GET /api/v1/accounts/{account.id}/labels' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/labels"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :administrator) }

      it 'returns all the labels in account' do
        create(:label, account: create(:account), title: 'other_account')
        get "/api/v1/accounts/#{account.id}/labels",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.body).to include(label.title)
        expect(response.body).not_to include('other_account')
      end
    end

    context 'when it is an authenticated agent' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'allows the account label catalog to be used by conversation selectors' do
        get "/api/v1/accounts/#{account.id}/labels", headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['payload'].pluck('id')).to eq([label.id])
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/labels/:id' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/labels/#{label.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:admin) { create(:user, account: account, role: :administrator) }

      it 'shows the contact' do
        get "/api/v1/accounts/#{account.id}/labels/#{label.id}",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.body).to include(label.title)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/labels' do
    let(:valid_params) { { label: { title: 'test' } } }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        expect { post "/api/v1/accounts/#{account.id}/labels", params: valid_params }.not_to change(Label, :count)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:admin) { create(:user, account: account, role: :administrator) }

      it 'creates the contact' do
        expect do
          post "/api/v1/accounts/#{account.id}/labels", headers: admin.create_new_auth_token,
                                                        params: valid_params
        end.to change(Label, :count).by(1)

        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/labels/:id' do
    let(:valid_params) { { title: 'Test_2' }  }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        put "/api/v1/accounts/#{account.id}/labels/#{label.id}",
            params: valid_params

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:admin) { create(:user, account: account, role: :administrator) }

      it 'updates the label' do
        patch "/api/v1/accounts/#{account.id}/labels/#{label.id}",
              headers: admin.create_new_auth_token,
              params: valid_params,
              as: :json

        expect(response).to have_http_status(:success)
        expect(label.reload.title).to eq('test_2')
      end

      it 'does not update a label from another account' do
        other_label = create(:label, account: create(:account))

        patch "/api/v1/accounts/#{account.id}/labels/#{other_label.id}", headers: admin.create_new_auth_token,
                                                                    params: valid_params, as: :json

        expect(response).to have_http_status(:not_found)
        expect(other_label.reload.title).not_to eq('test_2')
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/labels/:id' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/labels/#{label.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:admin) { create(:user, account: account, role: :administrator) }

      it 'deletes the label and enqueues label cleanup' do
        label_deleted_at = Time.zone.parse('2026-05-07 10:00:00 UTC')
        conversation.label_list.add(label.title)
        conversation.save!

        clear_enqueued_jobs

        travel_to(label_deleted_at) do
          expect do
            delete "/api/v1/accounts/#{account.id}/labels/#{label.id}", headers: admin.create_new_auth_token, as: :json
          end.to have_enqueued_job(Labels::RemoveAssociationsJob).with(
            label_title: label.title,
            account_id: account.id,
            label_deleted_at: label_deleted_at
          )
        end

        expect(response).to have_http_status(:ok)
        expect(Label.exists?(label.id)).to be(false)
      end
    end
  end
end
