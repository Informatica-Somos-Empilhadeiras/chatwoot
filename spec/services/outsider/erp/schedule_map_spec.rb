require 'rails_helper'

# OUTSIDER (Maps): "Mapa dos agendamentos". Um ponto por cliente com OS agendada no período (pelo Agendar do Chatwoot
# ou com substatus AGENDADO no Mais Prático), o ponto vindo do local exato do agendamento, do local principal de um
# contato ligado ou do endereço do cadastro; e a ficha do lado com os vazios completados pela consulta do CNPJ.
RSpec.describe Outsider::Erp::ScheduleMap do
  subject(:map) { described_class.new(account) }

  let(:account) { create(:account) }
  let(:from) { Time.zone.parse('2026-11-26 00:00') }
  let(:to) { Time.zone.parse('2026-11-30 23:59') }
  let(:items) do
    [
      { 'Empresa' => 'somosemp', 'CodigoOS' => 850, 'CodigoCliente' => 77, 'Nome' => 'TRANSPORTES ROTA', 'Cidade' => 'Goiânia', 'UF' => 'GO',
        'SubStatus' => '1-AGENDAR', 'Situacao' => 'ABERTA', 'NomeTecnico' => 'Téo', 'DataEntrada' => '2026-11-20' },
      { 'Empresa' => 'somosemp', 'CodigoOS' => 851, 'CodigoCliente' => 77, 'Nome' => 'TRANSPORTES ROTA', 'Situacao' => 'CONCLUÍDA',
        'DataEntrada' => '2026-11-01' },
      { 'Empresa' => 'somosemp', 'CodigoOS' => 900, 'CodigoCliente' => 88, 'Nome' => 'ARMAZEM SUL', 'SubStatus' => '2-AGENDADO (DF)',
        'Situacao' => 'ABERTA', 'NomeTecnico' => 'Bia', 'DataPrevisao' => '2026-11-27 00:00:00' },
      { 'Empresa' => 'somosemp', 'CodigoOS' => 901, 'CodigoCliente' => 99, 'Nome' => 'FORA DO PERIODO', 'SubStatus' => '2-AGENDADO',
        'DataPrevisao' => '2026-12-20 00:00:00' },
      { 'Empresa' => 'somosemp', 'CodigoOS' => 902, 'CodigoCliente' => 66, 'Nome' => 'LOGISTICA NORTE', 'SubStatus' => '2-AGENDADO',
        'DataPrevisao' => '2026-11-28 00:00:00' },
      { 'Empresa' => 'somosemp', 'CodigoOS' => 903, 'CodigoCliente' => 55, 'Nome' => 'SEM ENDERECO', 'SubStatus' => '2-AGENDADO',
        'DataPrevisao' => '2026-11-28 00:00:00' }
    ]
  end
  let(:records) do
    { 66 => { 'nome' => 'LOGISTICA NORTE', 'endereco' => 'Rua 5', 'numero' => '10', 'cidade' => 'Anápolis', 'uf' => 'GO' },
      55 => { 'nome' => 'SEM ENDERECO' },
      77 => { 'nome' => 'TRANSPORTES ROTA', 'documento' => '11.222.333/0001-81', 'bairro' => nil, 'cidade' => 'GOIANIA' } }
  end
  let(:contact) do
    create(:contact, account: account, name: 'Marcos',
                     additional_attributes: { 'outsider_erp_clients' => [{ 'empresa' => 'somosemp', 'codigo' => 88 }] })
  end

  before do
    account.update!(internal_attributes: { 'outsider_erp' => { 'enabled' => true, 'companies' => %w[somosemp], 'orders_enabled' => true } })
    allow_any_instance_of(Outsider::Erp::ServiceOrders).to receive(:items).and_return(items) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Outsider::Erp::CustomerRecord).to receive(:find) { |_, _company, code| records.fetch(code, {}) } # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Outsider::Geocoder).to receive(:search) do |_, query| # rubocop:disable RSpec/AnyInstance
      query.include?('Rua 5') ? [{ latitude: -16.33, longitude: -48.95, exact: false }] : []
    end
    Outsider::Erp::OrderSchedule.create!(account: account, company: 'somosemp', order_number: 850, title: 'OS 850',
                                         starts_at: Time.zone.parse('2026-11-26 14:00'), ends_at: Time.zone.parse('2026-11-26 15:00'),
                                         time_zone: 'America/Sao_Paulo', place_name: 'Galpão 2', latitude: -16.68, longitude: -49.25)
    Outsider::ContactPlace.create!(account: account, contact: contact, name: 'Depósito', latitude: -15.79, longitude: -47.88, main: true)
  end

  it 'places each scheduled client by the exact schedule point, a linked contact place or the record address' do # rubocop:disable RSpec/MultipleExpectations
    result = map.points(from: from, to: to)

    by_code = result[:clients].index_by { |row| row[:code] }
    expect(by_code.keys).to contain_exactly(77, 88, 66)
    expect(by_code[77]).to include(latitude: -16.68, source: 'schedule', place_name: 'Galpão 2', approximate: false)
    expect(by_code[77][:schedules].first).to include(order: 850, start: '2026-11-26T11:00:00', source: 'chatwoot', technician: 'Téo')
    expect(by_code[88]).to include(latitude: -15.79, source: 'contact')
    expect(by_code[88][:schedules].first).to include(order: 900, all_day: true, source: 'erp')
    expect(by_code[66]).to include(latitude: -16.33, source: 'address', approximate: true)
    expect(result[:missing].pluck(:code)).to eq([55])
    expect(result[:pending]).to eq(0)
    expect(result[:technicians]).to eq(%w[Bia Téo])
  end

  it 'filters by technician' do
    expect(map.points(from: from, to: to, technician: 'Bia')[:clients].pluck(:code)).to eq([88])
  end

  it 'builds the client sheet with the CNPJ lookup for empty fields, contacts, machines and only open orders' do
    allow_any_instance_of(Outsider::Crm::CompanyLookup).to receive(:perform) # rubocop:disable RSpec/AnyInstance
      .and_return(customer: { district: 'Setor Sul', city: 'Goiânia', company: 'TRANSPORTES ROTA LTDA' })
    allow_any_instance_of(Outsider::Erp::Rentals::ClientSummary).to receive(:build) # rubocop:disable RSpec/AnyInstance
      .and_return('contracts' => [{ 'numero' => 12, 'status' => 'ATIVO', 'maquinas' => [{ 'numero' => 5, 'descricao' => 'Empilhadeira' }] }],
                  'machines' => [{ 'numero' => 9, 'descricao' => 'Paleteira' }])
    allow_any_instance_of(Outsider::Erp::Client).to receive(:query_execute) do |_, sql| # rubocop:disable RSpec/AnyInstance
      if sql.include?('information_schema') then %w[CodigoCliente Nome Fone Email].map { |name| { 'COLUMN_NAME' => name } }
      else
        [{ 'nome' => ' Carla ', 'fone' => '62 3333-0000', 'email' => nil, 'cargo' => nil }, { 'nome' => nil, 'fone' => nil, 'email' => nil }]
      end
    end

    sheet = map.client('somosemp', 77)

    expect(sheet[:completed]).to eq('bairro' => 'Setor Sul')
    expect(sheet[:erp_contacts]).to eq([{ 'nome' => 'Carla', 'fone' => '62 3333-0000', 'email' => nil, 'cargo' => nil }])
    expect(sheet[:machines].map { |row| row.values_at('numero', 'kind', 'contrato') }).to eq([[5, 'rented', 12], [9, 'own', nil]])
    expect(sheet[:orders].pluck(:code)).to eq([850])
  end
end
