require 'rails_helper'

RSpec.describe Outsider::Crm::CompanyLookup do
  let(:cnpj) { '11222333000181' }
  let(:cnpja_url) { "https://open.cnpja.com/office/#{cnpj}" }
  let(:cnpjws_url) { "https://publica.cnpj.ws/cnpj/#{cnpj}" }
  let(:brasilapi_url) { "https://brasilapi.com.br/api/cnpj/v1/#{cnpj}" }
  let(:cnpja_body) do
    { taxId: cnpj, alias: 'Somos', company: { name: 'SOMOS EMPILHADEIRAS LTDA', members: [{ person: { name: 'Fulano' } }] },
      address: { street: 'Avenida Anhanguera', number: '100', details: 'Sala 2', district: 'Setor Oeste', city: 'Goiânia',
                 state: 'GO', zip: '74110010' },
      phones: [{ area: '62', number: '32221234' }], emails: [{ address: 'financeiro@somos.com.br' }],
      registrations: [{ number: '109876543', state: 'SP', enabled: true }, { number: '101234567', state: 'GO', enabled: true }] }
  end
  let(:cnpjws_body) do
    { razao_social: 'SOMOS EMPILHADEIRAS LTDA',
      estabelecimento: { tipo_logradouro: 'AVENIDA', logradouro: 'ANHANGUERA', numero: '100', bairro: 'SETOR OESTE', cep: '74110010',
                         ddd1: '62', telefone1: '32221234', email: 'contato@somos.com.br', cidade: { nome: 'Goiânia' }, estado: { sigla: 'GO' },
                         inscricoes_estaduais: [{ inscricao_estadual: '101234567', ativo: true, estado: { sigla: 'GO' } }] } }
  end

  def json(body, status: 200)
    { status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  it 'fills only the proposal fields from the SEFAZ registry and stops when nothing is missing' do
    stub_request(:get, cnpja_url).to_return(json(cnpja_body))

    result = described_class.new('11.222.333/0001-81').perform

    expect(result).to eq(
      customer: { 'company' => 'SOMOS EMPILHADEIRAS LTDA', 'document' => '11.222.333/0001-81', 'state_registration' => '101234567',
                  'address' => 'Avenida Anhanguera, 100 - Sala 2', 'district' => 'Setor Oeste', 'city' => 'Goiânia', 'state' => 'GO',
                  'zip' => '74110-010', 'phone' => '(62) 3222-1234', 'email' => 'financeiro@somos.com.br' },
      sources: ['cnpja']
    )
    expect(a_request(:get, cnpjws_url)).not_to have_been_made
  end

  it 'completes from SINTEGRA what the first service did not bring, and skips the other states IE' do
    stub_request(:get, cnpja_url).to_return(json(cnpja_body.merge(emails: [], registrations: [{ number: '1098', state: 'SP', enabled: true }])))
    stub_request(:get, cnpjws_url).to_return(json(cnpjws_body))

    result = described_class.new(cnpj).perform

    expect(result[:customer]).to include('state_registration' => '101234567', 'email' => 'contato@somos.com.br',
                                         'address' => 'Avenida Anhanguera, 100 - Sala 2')
    expect(result[:sources]).to eq(%w[cnpja cnpjws])
  end

  it 'falls back when a service limits the lookups and tells apart not found from unavailable' do
    stub_request(:get, cnpja_url).to_return(status: 429)
    stub_request(:get, cnpjws_url).to_timeout
    stub_request(:get, brasilapi_url).to_return(json({ razao_social: 'SOMOS EMPILHADEIRAS LTDA', uf: 'GO', ddd_telefone_1: '6232221234' }))

    expect(described_class.new(cnpj).perform).to include(sources: ['brasilapi'])

    stub_request(:get, brasilapi_url).to_return(status: 503)
    expect { described_class.new(cnpj).perform }.to raise_error(described_class::Unavailable)

    stub_request(:get, cnpja_url).to_return(json({ message: 'not found' }, status: 404))
    expect { described_class.new(cnpj).perform }.to raise_error(described_class::NotFound)
  end

  it 'refuses an oversized answer' do
    stub_const('Outsider::Crm::CompanyLookup::MAX_BYTES', 100)
    stub_request(:get, cnpja_url).to_return(json(cnpja_body))
    stub_request(:get, cnpjws_url).to_return(status: 429)
    stub_request(:get, brasilapi_url).to_return(status: 429)

    expect { described_class.new(cnpj).perform }.to raise_error(described_class::Unavailable)
  end

  it 'checks the CNPJ digits, including the alphanumeric CNPJ' do
    expect(described_class.normalize('12.abc.345/01de-35')).to eq('12ABC34501DE35')
    expect(described_class.normalize('11.222.333/0001-82')).to be_nil
    expect(described_class.normalize('00000000000000')).to be_nil
    expect { described_class.new('123.456.789-09') }.to raise_error(described_class::Invalid)
  end
end
