require 'rails_helper'

# OUTSIDER (Maps): o Mapa dos agendamentos abre para quem tem "Vê" na linha do perfil; gravar os vazios do cliente no ERP
# pede "Gravar no ERP" ligado e "Usa" em "Completar cadastro do cliente no ERP" (agente não tem por padrão).
RSpec.describe 'Outsider ERP schedule map', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/outsider/erp/schedule_map" }
  let(:write_enabled) { true }

  before do
    account.update!(internal_attributes: {
                      'outsider_erp' => { 'enabled' => true, 'companies' => %w[somosemp], 'orders_enabled' => true,
                                          'write_enabled' => write_enabled },
                      'outsider_google_maps_map_id' => 'abc123vector'
                    })
    allow_any_instance_of(Outsider::Erp::ServiceOrders).to receive(:items).and_return([]) # rubocop:disable RSpec/AnyInstance
  end

  it 'shows the period to an agent, without the ERP write' do
    get base, params: { from: '2026-11-26', to: '2026-11-30' }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('clients' => [], 'missing' => [], 'pending' => 0, 'can_complete' => false, 'map_id' => 'abc123vector')
  end

  it 'does not let an agent write the client record' do
    post "#{base}/complete", params: { company: 'somosemp', code: 77, values: { bairro: 'Centro' } }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:forbidden)
  end

  it 'writes the empty fields for an administrator' do
    completer = instance_double(Outsider::Erp::ClientCompleter, call: { written: ['bairro'], record: { 'bairro' => 'CENTRO' } })
    allow(Outsider::Erp::ClientCompleter).to receive(:new).and_return(completer)

    post "#{base}/complete", params: { company: 'somosemp', code: 77, values: { bairro: 'Centro', nome: 'X' } },
                             headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['written']).to eq(['bairro'])
    expect(completer).to have_received(:call).with('somosemp', 77, { 'bairro' => 'Centro' })
  end

  context 'when "Gravar no ERP" is off' do
    let(:write_enabled) { false }

    it 'refuses the write even for an administrator' do
      post "#{base}/complete", params: { company: 'somosemp', code: 77, values: { bairro: 'Centro' } }, headers: admin.create_new_auth_token,
                               as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
