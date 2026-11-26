require 'rails_helper'

# OUTSIDER (Maps): "Gravar no Mais Prático" no Mapa dos agendamentos. Só com "Gravar no ERP" ligado, só os campos que
# podem ser completados, e o UPDATE só põe valor em coluna vazia (a condição vai na própria SQL). O query_execute é
# simulado conforme a SQL recebida.
RSpec.describe Outsider::Erp::ClientCompleter do
  subject(:completer) { described_class.new(account) }

  let(:account) { create(:account) }
  let(:sqls) { [] }
  let(:write_enabled) { true }
  let(:row) do
    { 'codigo' => 77, 'nome' => 'TRANSPORTES ROTA', 'documento' => '11222333000181', 'bairro' => nil, 'cidade' => 'GOIANIA', 'email' => '' }
  end

  before do
    account.update!(internal_attributes: { 'outsider_erp' => { 'enabled' => true, 'companies' => %w[somosemp], 'orders_enabled' => true,
                                                               'write_enabled' => write_enabled } })
    allow_any_instance_of(Outsider::Erp::ClientProfile).to receive(:uppercase?).and_return(true) # rubocop:disable RSpec/AnyInstance
    stub_request(:put, %r{/dashboard/api/query_execute}).to_return do |request|
      sql = JSON.parse(request.body)['SQL_Execute']
      sqls << sql
      { status: 200, body: answer(sql).to_json }
    end
  end

  def answer(sql)
    if sql.include?('CHARACTER_MAXIMUM_LENGTH') then [{ 'nome' => 'Bairro', 'tamanho' => 10 }, { 'nome' => 'email', 'tamanho' => 80 }]
    elsif sql.include?('information_schema') then %w[CodigoCliente Nome CPF_CNPJ Bairro Cidade email].map { |name| { 'COLUMN_NAME' => name } }
    elsif sql.start_with?('UPDATE')
      row['bairro'] = 'JARDIM AMER'
      row['email'] = 'compras@rota.com.br'
      []
    else
      [row.dup]
    end
  end

  it 'fills only empty columns, in upper case and cut to the column size, and never the name or the document' do # rubocop:disable RSpec/MultipleExpectations
    result = completer.call('somosemp', 77, 'bairro' => 'Jardim América Sul', 'email' => 'compras@rota.com.br', 'cidade' => 'Anápolis',
                                            'nome' => 'OUTRO NOME')

    update = sqls.find { |sql| sql.start_with?('UPDATE') }
    expect(update).to start_with('UPDATE somosemp.clientes SET ')
    expect(update).to include("`Bairro` = IF(`Bairro` IS NULL OR TRIM(`Bairro`) = '', 'JARDIM AMÉ', `Bairro`)")
    expect(update).to include("`email` = IF(`email` IS NULL OR TRIM(`email`) = '', 'compras@rota.com.br', `email`)")
    expect(update).to include("`Cidade` = IF(`Cidade` IS NULL OR TRIM(`Cidade`) = '', 'ANÁPOLIS', `Cidade`)")
    expect(update).not_to include('Nome')
    expect(update).to end_with('WHERE CodigoCliente = 77 LIMIT 1')
    expect(result[:written]).to contain_exactly('bairro', 'email')
    expect(result[:record]['bairro']).to eq('JARDIM AMER')
  end

  context 'when "Gravar no ERP" is off' do
    let(:write_enabled) { false }

    it 'writes nothing' do
      expect { completer.call('somosemp', 77, 'bairro' => 'Centro') }.to raise_error(described_class::Disabled)
      expect(sqls).to be_empty
    end
  end
end
