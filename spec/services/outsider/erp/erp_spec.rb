require 'rails_helper'

RSpec.describe 'Outsider ERP' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:base) { 'https://somos-backend.inntegra.com.br' }
  let(:orders_json) do
    [
      { 'CodigoOS' => 907, 'Empresa' => 'somosemp', 'CodigoCliente' => 716, 'Nome' => 'GDS - SUPERMERCADO ALVORADA GOIANO LTDA',
        'StatusKanban' => 'RETIRADA', 'SubStatus' => '2-AGENDADO', 'DataEntrada' => '2026-11-11T03:00:00.000Z', 'Defeitos' => '.',
        'NomeTecnico' => 'HENRIQUE', 'Lixo' => 'x' },
      { 'CodigoOS' => 907, 'Empresa' => 'somosfilial', 'CodigoCliente' => 716, 'Nome' => 'OUTRO CLIENTE LTDA',
        'StatusKanban' => 'NEGOCIAÇÃO', 'SubStatus' => '1-AGENDAR ATENDIMENTO (DF)', 'DataEntrada' => '2026-11-12T03:00:00.000Z' },
      { 'CodigoOS' => 939, 'Empresa' => 'somosemp', 'CodigoCliente' => 716, 'Nome' => 'GDS - SUPERMERCADO ALVORADA GOIANO LTDA',
        'StatusKanban' => 'NEGOCIAÇÃO', 'SubStatus' => '1- AGENDAR ATENDIMENTO', 'DataEntrada' => '2026-11-17T03:00:00.000Z' }
    ].to_json
  end
  let(:settings) { Outsider::Erp::Settings.new(account) }

  before do
    Redis::Alfred.delete("outsider_erp:#{account.id}:os")
    Redis::Alfred.delete("outsider_erp:#{account.id}:os:lock")
    settings.update('enabled' => true, 'companies' => %w[somosemp somosfilial], 'device_id' => 'abc123')
    stub_request(:get, %r{#{base}/KanbanOrdemServico/api/valoresDash}).to_return(status: 200, body: orders_json)
  end

  describe Outsider::Erp::Settings do
    it 'only accepts the Inntegra API over https and known field names' do
      expect { settings.update('base_url' => 'http://somos-backend.inntegra.com.br') }.to raise_error(Outsider::Erp::Settings::Invalid)
      expect { settings.update('base_url' => 'https://evil.example.com') }.to raise_error(Outsider::Erp::Settings::Invalid)
      expect { settings.update('extra_fields' => [{ 'field' => 'SubStatus', 'endpoint' => 'UpdateSubStatusOS' }]) }
        .to raise_error(Outsider::Erp::Settings::Invalid)

      settings.update('extra_fields' => [{ 'field' => 'Observacoes', 'endpoint' => 'UpdateObservacoes' }])
      expect(settings.writable_fields).to eq('Defeitos' => 'UpdateDefeitos', 'Observacoes' => 'UpdateObservacoes')
    end

    it 'never sends the device id back to the screen and keeps it when left blank' do
      settings.update('device_id' => '')
      expect(described_class.new(account).device_id).to eq('abc123')
      expect(settings.as_json).not_to have_key('device_id')
      expect(settings.as_json['device_id_set']).to be(true)
    end
  end

  describe Outsider::Erp::ServiceOrders do
    let(:orders) { described_class.new(account) }

    it 'asks the ERP once, with the configured companies, and keeps only the panel fields' do
      2.times { described_class.new(account).items }

      expect(a_request(:get, /valoresDash/).with(headers: { 'x-device-id' => 'abc123' })).to have_been_made.once
      expect(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.first.uri.query)
        .to include('listaEmpresas%5B%5D=somosemp&listaEmpresas%5B%5D=somosfilial')
      expect(orders.items.first).not_to have_key('Lixo')
    end

    it 'filters by company and customer code (codes repeat between companies)' do
      list = orders.for_clients([{ 'empresa' => 'somosemp', 'codigo' => 716 }])
      expect(list.pluck('CodigoOS')).to eq([939, 907])
      expect(list.pluck('Empresa').uniq).to eq(['somosemp'])
    end

    it 'finds customers by name and groups the board by sub-status without the branch suffix' do
      expect(orders.customers('supermercado alvorada')).to contain_exactly(include(empresa: 'somosemp', codigo: 716, count: 2))
      names = orders.board[:columns].pluck(:name)
      expect(names).to eq(['1-AGENDAR ATENDIMENTO', '2-AGENDADO'])
    end

    it 'serves the old copy while the ERP is down' do
      orders.items
      travel 10.minutes do
        stub_request(:get, /valoresDash/).to_return(status: 500)
        fresh = described_class.new(account)
        expect(fresh.items.size).to eq(3)
        expect(fresh.meta[:stale]).to be(true)
      end
    end
  end

  describe Outsider::Erp::Writer do
    let(:writer) { described_class.new(account: account, user: user) }
    let!(:put_substatus) { stub_request(:put, "#{base}/KanbanOrdemServico/api/UpdateSubStatusOS/907").to_return(status: 200, body: '[]') }
    let!(:put_history) { stub_request(:put, "#{base}/KanbanOrdemServico/api/GravaHistoricoSubStatusOS/907").to_return(status: 200, body: '[]') }

    it 'refuses while writing is off' do
      expect { writer.substatus(company: 'somosemp', code: 907, value: '1- AGENDAR ATENDIMENTO') }.to raise_error(Outsider::Erp::Writer::Disabled)
    end

    context 'with writing on' do
      before { settings.update('write_enabled' => true, 'user_erp_ids' => { user.id.to_s => '55' }) }

      it 'changes the sub-status and writes the ERP history, with the company of the order itself' do
        conversation = create(:conversation, account: account)
        order = writer.substatus(company: 'somosemp', code: 907, value: '1- AGENDAR ATENDIMENTO', conversation: conversation)

        expect(put_substatus.with(body: { 'SubStatus' => '1- AGENDAR ATENDIMENTO', 'listaEmpresas' => %w[somosemp somosfilial],
                                          'Empresa' => 'somosemp' })).to have_been_made
        expect(put_history.with(body: { 'SubStatusAntigo' => '2-AGENDADO', 'SubStatusNovo' => '1- AGENDAR ATENDIMENTO',
                                        'listaEmpresas' => %w[somosemp somosfilial], 'idUsuario' => '55', 'Empresa' => 'somosemp' }))
          .to have_been_made
        expect(order['SubStatus']).to eq('1- AGENDAR ATENDIMENTO')
        expect(Outsider::Erp::ServiceOrders.new(account).find('somosemp', 907)['SubStatus']).to eq('1- AGENDAR ATENDIMENTO')
        expect(conversation.messages.last).to have_attributes(private: true)
        expect(conversation.messages.last.content).to include('OS 907')
      end

      it 'refuses an order outside the mirror, a value from another branch and an unknown field' do
        expect { writer.substatus(company: 'somosgo', code: 907, value: '2-AGENDADO') }.to raise_error(Outsider::Erp::Writer::Invalid)
        expect { writer.substatus(company: 'somosemp', code: 907, value: '1-AGENDAR ATENDIMENTO (DF)') }
          .to raise_error(Outsider::Erp::Writer::Invalid)
        expect { writer.field(company: 'somosemp', code: 907, field: 'Observacoes', value: 'x') }.to raise_error(Outsider::Erp::Writer::Invalid)
        expect(put_substatus).not_to have_been_made
      end

      it 'writes the defects field' do
        put = stub_request(:put, "#{base}/KanbanOrdemServico/api/UpdateDefeitos/907")
              .with(body: { 'Defeitos' => 'Vazamento', 'listaEmpresas' => %w[somosemp somosfilial], 'Empresa' => 'somosemp' })
              .to_return(status: 200, body: '[]')

        writer.field(company: 'somosemp', code: 907, field: 'Defeitos', value: 'Vazamento')
        expect(put).to have_been_made
      end
    end
  end

  describe Outsider::Erp::ContactLink do
    it 'keeps the links in the contact without touching its other attributes' do
      contact = create(:contact, account: account, additional_attributes: { 'company_name' => 'GDS' })
      link = described_class.new(contact)
      link.add(company: 'somosemp', code: 716, name: 'GDS', settings: settings)
      link.add(company: 'somosemp', code: 716, name: 'GDS', settings: settings)

      expect(contact.reload.additional_attributes).to include('company_name' => 'GDS',
                                                              'outsider_erp_clients' => [{ 'empresa' => 'somosemp', 'codigo' => 716,
                                                                                           'nome' => 'GDS' }])
      expect { link.add(company: 'outraempresa', code: 1, name: 'X', settings: settings) }.to raise_error(Outsider::Erp::ContactLink::Invalid)
      expect(link.remove(company: 'somosemp', code: 716)).to eq([])
    end
  end
end
