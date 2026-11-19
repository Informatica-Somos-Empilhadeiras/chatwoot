require 'rails_helper'

# OUTSIDER: listas que abrem prontas (clientes, produtos, formas de pagamento), lendo do ERP só o que existe: as colunas
# vêm do information_schema (Outsider::Erp::Schema). O query_execute é simulado conforme a SQL recebida.
RSpec.describe 'Outsider ERP lists to pick from' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:settings) { Outsider::Erp::Settings.new(account) }
  let(:columns) do
    { 'clientes' => %w[CodigoCliente Nome Fantasia CPF_CNPJ Cidade UF Fone Celular Email],
      'produtos' => %w[CodigoProduto Descricao ClasFiscal] }
  end
  let(:customers) do
    {
      'somosemp' => [
        { 'codigo' => 800, 'nome' => 'ACME EMPILHADEIRAS', 'uf' => 'DF' },
        { 'codigo' => 716, 'nome' => 'GDS - SUPERMERCADO ALVORADA GOIANO LTDA', 'fantasia' => 'GDS', 'documento' => '12.345.678/0001-90',
          'cidade' => 'GOIÂNIA', 'uf' => 'GO', 'fone0' => '(62) 3333-4444', 'fone1' => '62 9 9999-8888' }
      ],
      'somosfilial' => [{ 'codigo' => 716, 'nome' => 'OUTRO CLIENTE LTDA' }]
    }
  end
  let!(:erp) do
    stub_request(:put, %r{/dashboard/api/query_execute}).to_return do |request|
      { status: 200, body: answer(JSON.parse(request.body)['SQL_Execute']).to_json }
    end
  end

  def answer(sql)
    if sql.include?('information_schema')
      columns.fetch(sql[/LOWER\(TABLE_NAME\) = '(\w+)'/, 1], []).map { |name| { 'COLUMN_NAME' => name } }
    elsif (bank = sql[/FROM (\w+)\.clientes/, 1]) then customers.fetch(bank, [])
    elsif sql.include?('.produtos') then [{ 'codigo' => 1234, 'descricao' => ' EMPILHADEIRA  ELETRICA ' }]
    elsif (bank = sql[/FROM (\w+)\.formapagto/, 1]) then payment_terms(bank)
    else
      []
    end
  end

  def payment_terms(bank)
    return [{ 'Codigo' => 3, 'Descricao' => 'BOLETO 28' }] unless bank == 'somosemp'

    [{ 'Codigo' => 3, 'Descricao' => 'BOLETO' }, { 'Codigo' => 1, 'Descricao' => 'A VISTA' }]
  end

  before do
    settings.update('enabled' => true, 'companies' => %w[somosemp somosfilial], 'device_id' => 'abc')
  end

  describe Outsider::Erp::Customers do
    subject(:directory) { described_class.new(account) }

    before { directory.snapshot.refresh! }

    it 'reads only the columns that exist, bank by bank, and never sends the phones to the screen' do
      data_sql = a_request(:put, %r{/query_execute}).with do |req|
        ['FROM somosemp.clientes T', 'T.`CPF_CNPJ` AS documento', 'T.`Celular` AS fone1'].all? { |part| req.body.include?(part) }
      end
      expect(data_sql).to have_been_made.once
      expect(directory.search('')).to all(satisfy { |row| !row.keys.intersect?(%w[fones busca]) })
    end

    it 'filters by name words, by code and by part of the CPF/CNPJ' do
      expect(directory.search('supermercado alvorada').pluck('codigo')).to eq([716])
      expect(directory.search('716').map { |row| row.values_at('empresa', 'codigo') }).to contain_exactly(['somosemp', 716], ['somosfilial', 716])
      expect(directory.search('12.345.678').pluck('nome')).to eq(['GDS - SUPERMERCADO ALVORADA GOIANO LTDA'])
      expect(directory.search('').pluck('nome')).to eq(['ACME EMPILHADEIRAS', 'GDS - SUPERMERCADO ALVORADA GOIANO LTDA', 'OUTRO CLIENTE LTDA'])
    end

    it 'puts the customers that look like the contact first, saying why' do
      contact = create(:contact, account: account, name: 'Maria', phone_number: '+5562999998888')
      list = directory.list('', contact: contact)
      expect(list.first).to include('codigo' => 716, 'empresa' => 'somosemp', 'motivo' => 'telefone')
      expect(list.size).to eq(3)

      by_company = create(:contact, account: account, name: 'Joao', additional_attributes: { 'company_name' => 'Acme' })
      expect(directory.suggestions(by_company).first).to include('codigo' => 800, 'motivo' => 'nome')
    end

    it 'keeps the column lookup cached instead of asking the ERP every time' do
      described_class.new(account).snapshot.refresh!
      expect(a_request(:put, %r{/query_execute}).with { |req| req.body.include?('information_schema') }).to have_been_made.times(2)
    end
  end

  it 'lists the products of a unit, ready before typing, and filters by number or words' do
    catalog = Outsider::Erp::Catalog.new(account)
    expect(catalog.search('somosemp', '')).to contain_exactly(include(codigo: 1234, descricao: 'EMPILHADEIRA ELETRICA', tipo: 0, ncm: nil))
    catalog.search('somosemp', 'empil elet')
    expect(a_request(:put, %r{/query_execute}).with do |req|
      req.body.include?("P.`Descricao` LIKE '%empil%' AND P.`Descricao` LIKE '%elet%'")
    end).to have_been_made
    expect { catalog.search('outra', '') }.to raise_error(ArgumentError)
  end

  it 'joins the payment terms of every unit, showing different names for the same code' do
    expect(Outsider::Erp::PaymentTerms.new(account).list).to eq([{ codigo: 1, descricao: 'A VISTA' }, { codigo: 3, descricao: 'BOLETO / BOLETO 28' }])
  end

  it 'refuses column names that do not look like columns' do
    expect { Outsider::Erp::Sql.column('Nome; DROP') }.to raise_error(ArgumentError)
    expect(Outsider::Erp::Sql.column('CPF_CNPJ')).to eq('`CPF_CNPJ`')
    expect(erp).not_to have_been_requested
  end
end
