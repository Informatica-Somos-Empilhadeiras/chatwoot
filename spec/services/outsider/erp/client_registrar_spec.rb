require 'rails_helper'

# OUTSIDER: "Cadastrar cliente no ERP" (Outsider::Erp::ClientRegistrar): só pela função do Mais Prático, desligado por
# padrão, sem cliente repetido (CPF/CNPJ procurado sem máscara) e o endereço de cobrança/entrega só no cliente que a tela
# criou. O query_execute é simulado conforme a SQL recebida.
RSpec.describe Outsider::Erp::ClientRegistrar do
  subject(:registrar) { described_class.new(account, user: user) }

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, name: 'Ana Souza') }
  let(:contact) { create(:contact, account: account, name: 'Maria') }
  let(:sqls) { [] }
  let(:existing_rows) { [] }
  let(:stored_key) { nil }
  let(:columns) { %w[CodigoCliente Nome CPF_CNPJ TipoPessoa Cep CodigoIntegracaoMobile] }
  let(:params) do
    { 'company' => 'somosemp', 'documento' => '11.222.333/0001-81', 'nome' => "Empilhadeiras d'Oeste", 'apelido' => 'Oeste',
      'cep' => '74000000', 'endereco' => "Rua 10 #{'x' * 70}", 'numero' => '100', 'bairro' => 'Centro', 'cidade' => 'Goiânia', 'uf' => 'go',
      'email' => 'Compras@Oeste.com.br', 'vendedor' => '7', 'contato_nome' => 'Maria', 'contato_telefone' => '62 98888-7777' }
  end

  before do
    account.update!(internal_attributes: { 'outsider_erp' => { 'enabled' => true, 'companies' => %w[somosemp], 'client_write_enabled' => true } })
    stub_request(:put, %r{/dashboard/api/query_execute}).to_return do |request|
      sql = JSON.parse(request.body)['SQL_Execute']
      sqls << sql
      { status: 200, body: answer(sql).to_json }
    end
  end

  def answer(sql)
    if sql.include?('information_schema.PARAMETERS') then [{ 'nome' => 'v_nome', 'tamanho' => 100 }, { 'nome' => 'v_endereco', 'tamanho' => 80 }]
    elsif sql.include?("IN ('clientes', 'contatosclientes')") then [{ 'nome' => 'clientes.enderecocob', 'tamanho' => 60 }]
    elsif sql.include?('information_schema') then columns.map { |name| { 'COLUMN_NAME' => name } }
    else
      erp_answer(sql)
    end
  end

  def erp_answer(sql)
    if sql.include?('DESC LIMIT 300')
      [{ 'documento' => '12.345.678/0001-95', 'tipo' => 2, 'nome' => 'ACME LTDA', 'cep' => '74000-000' },
       { 'documento' => '529.982.247-25', 'tipo' => 1, 'nome' => 'JOSE', 'cep' => '74000-000' }]
    elsif sql.include?('UPPER(REPLACE(') then existing_rows
    elsif sql.include?('AS chave') then [{ 'chave' => stored_key || sqls.join[/'(CWC[A-Z0-9]+)'\) AS codigo/, 1] }]
    elsif sql.match?(/sp_Cadastra(Endereco)?Cliente\(/) then [{ 'codigo' => 901 }]
    else
      []
    end
  end

  def writes = sqls.grep(/\ASELECT somosemp\.sp_Cadastra/)

  it 'registers through the ERP function, in the unit habits, and copies the address only to the new client' do
    result = registrar.call(params, contact: contact)

    expect(result).to include('empresa' => 'somosemp', 'codigo' => 901, 'existente' => false, 'vinculado' => true,
                              'nome' => "EMPILHADEIRAS D'OESTE", 'documento' => '11.222.333/0001-81')
    call = writes.first
    expect(call).to start_with("SELECT somosemp.sp_CadastraCliente(2, 'EMPILHADEIRAS D\\'OESTE', 'OESTE', '11.222.333/0001-81', NULL, ")
    expect(call).to include("'74000-000', 'GO', 'GOIÂNIA'", "'compras@oeste.com.br', 'Pré-cadastro feito no Chatwoot por Ana Souza em",
                            "7, 0, 'MARIA', NULL, '62 98888-7777', 'MARIA', NULL, '62 98888-7777', 'CWC")
    # o endereço cabe na menor coluna (EnderecoCob, 60) e vai para cobrança e entrega
    expect(call[/'(RUA 10 x*)'/i, 1].length).to eq(60)
    expect(writes.drop(1).map { |sql| sql[/'(COBRANCA|ENTREGA)'/, 1] }).to eq(%w[COBRANCA ENTREGA])
    expect(Outsider::Erp::ContactLink.new(contact.reload).links).to include(include('empresa' => 'somosemp', 'codigo' => 901))
  end

  it 'returns the existing client for a document already in the unit, with or without mask, without calling the function' do
    existing_rows << { 'codigo' => 716, 'nome' => ' GDS ', 'documento' => '11222333000181' }

    expect(registrar.call(params)).to include('codigo' => 716, 'nome' => 'GDS', 'existente' => true, 'vinculado' => false)
    expect(writes).to be_empty
    expect(sqls.find { |sql| sql.include?('UPPER(REPLACE(') }).to include("= '11222333000181'")
  end

  context 'when the function hands back a client this screen did not create' do
    let(:stored_key) { 'MOBILE123' }

    it 'never touches its address' do
      expect(registrar.call(params)).to include('codigo' => 901, 'existente' => true)
      expect(writes.size).to eq(1)
    end
  end

  it 'refuses bad data, a unit outside the settings and a disabled setting before any write' do
    expect { registrar.call(params.merge('documento' => '11.222.333/0001-80', 'email' => 'x@')) }
      .to raise_error(described_class::Invalid) { |error| expect(error.fields).to contain_exactly('documento', 'email') }
    expect { registrar.call(params.merge('company' => 'outrocliente')) }.to raise_error(described_class::Invalid, 'empresa')

    account.update!(internal_attributes: { 'outsider_erp' => { 'enabled' => true, 'companies' => %w[somosemp] } })
    expect { described_class.new(account, user: user).call(params) }.to raise_error(described_class::Disabled)
    expect(writes).to be_empty
    expect(sqls.join).not_to include('outrocliente')
  end

  it 'accepts the new alphanumeric CNPJ and checks the CPF digits' do
    expect(Outsider::Erp::ClientForm.valid_document?('12ABC34501DE35')).to be(true)
    expect(Outsider::Erp::ClientForm.valid_document?('12ABC34501DE36')).to be(false)
    expect(Outsider::Erp::ClientForm.valid_document?('52998224725')).to be(true)
    expect(Outsider::Erp::ClientForm.valid_document?('11111111111')).to be(false)
  end
end
