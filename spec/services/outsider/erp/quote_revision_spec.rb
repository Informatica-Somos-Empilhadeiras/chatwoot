require 'rails_helper'

# OUTSIDER: editar pelo chat um orçamento já gravado no ERP (decisão de 20/11/2026: "editar tudo, com travas"). Só em
# NEGOCIAÇÃO e sem ninguém com ele aberto no Mais Prático; as linhas saem e entram de novo pelas funções do ERP e toda
# escrita fora delas leva a trava no WHERE. O ERP é o OutsiderFakeErp (spec/support) com o "em uso" do orçamento.
RSpec.describe 'Outsider ERP recorded quote editing' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:settings) { Outsider::Erp::Settings.new(account) }
  let(:quote) { { 'status' => 'NEGOCIAÇÃO', 'em_uso' => 0 } }
  let(:unlocked) { [true] }
  let!(:erp) do
    fake = OutsiderFakeErp.new(number: 4119)
    extra = quote
    open_now = unlocked
    fake.define_singleton_method(:answer) do |sql|
      if sql.include?('information_schema') && sql.include?("'orcamento'")
        super(sql) + %w[OrcamentoEmUtilizacao DataEmUtilizacao NomeUserEmUtilizacao].map { |name| { 'COLUMN_NAME' => name } }
      elsif sql.start_with?('SELECT O.codigoorcamento AS codigo') then open_now.first ? [{ 'codigo' => 4119 }] : []
      elsif sql.include?('.orcamento O WHERE O.`codigoorcamento`') then super(sql).map { |row| row.merge(extra) }
      else
        super(sql)
      end
    end
    stub_fake_erp(fake)
  end
  let(:revision) { Outsider::Erp::QuoteRevision.new(account, user) }

  before do
    settings.update('enabled' => true, 'companies' => %w[somosemp], 'device_id' => 'abc', 'quote_write_enabled' => true,
                    'quote_discount_approval' => false)
  end

  def save(budget)
    budget.update!(status: :submitting)
    Outsider::Erp::QuoteUpdater.new(budget.reload, user: user).call
  end

  it 'opens the edit with the items and conditions that are in the ERP now' do
    budget = revision.start(company: 'somosemp', number: 4119)

    expect(budget).to be_revising
    expect(budget.items.pluck('codigo')).to eq([923, 491, 503])
    expect(budget.terms).to include('contato' => 'Gilmar Souza', 'vendedor' => 7, 'validade' => '10 dias')
    expect(erp.writes_made).to be_empty
  end

  it 'refuses a quote that is not in NEGOCIAÇÃO or is open in the desktop app right now' do
    quote['status'] = 'FECHADO'
    expect { revision.start(company: 'somosemp', number: 4119) }.to raise_error(Outsider::Erp::QuoteRevision::Invalid, 'status')

    quote.merge!('status' => 'NEGOCIAÇÃO', 'em_uso' => 1, 'em_uso_por' => 'CRISTIANE', 'em_uso_desde' => 5.minutes.ago.iso8601)
    expect { revision.start(company: 'somosemp', number: 4119) }.to raise_error(Outsider::Erp::QuoteRevision::Invalid, 'em_uso')
  end

  it 'rewrites the lines through the ERP functions with the lock in every other write, keeping the number' do
    budget = revision.start(company: 'somosemp', number: 4119)
    Outsider::Erp::BudgetForm.new(budget, settings).apply(
      'items' => [budget.items.first.merge('quantidade' => 2), budget.items.last], 'terms' => { 'contato' => 'Novo', 'forma_pagto' => 99 }
    )
    save(budget)

    lock = "O.`Status` = 'NEGOCIAÇÃO' AND NOT (IFNULL(O.`OrcamentoEmUtilizacao`, 0) = 1"
    delete = erp.sqls.find { |sql| sql.start_with?('DELETE') }
    expect(delete).to start_with('DELETE FROM somosemp.detalheorcamento WHERE CodigoOrcamento = 4119 AND EXISTS').and include(lock)
    expect(erp.sqls.grep(/sp_CadastraItemOrcamento\(4119, 923, 2\.0,/).size).to eq(1)
    expect(erp.sqls.find { |sql| sql.start_with?('INSERT INTO') }).to include(lock).and include('P.Tipo = 1')
    expect(erp.sqls.find { |sql| sql.start_with?('UPDATE') }).to include("O.`Contato` = 'Novo'", lock)
    expect(erp.sqls.grep(/sp_CadastraOrcamento|sp_FinalizaOrcamento\(4119\)/)).to eq(['SELECT somosemp.sp_FinalizaOrcamento(4119) AS resultado'])
    expect(budget.reload).to have_attributes(status: 'imported', erp_number: 4119)
    expect(budget.erp_result['edits'].last).to include('user_id' => user.id, 'items' => 2)
  end

  it 'touches nothing when someone opened the quote in the desktop app after the edit started' do
    budget = revision.start(company: 'somosemp', number: 4119)
    unlocked[0] = false

    expect { save(budget) }.to raise_error(Outsider::Erp::QuoteCreator::Invalid, 'em_uso')
    expect(erp.sqls.grep(/\A(DELETE|INSERT|UPDATE)|sp_Cadastra/)).to be_empty
  end

  it 'discards the edit without writing to the ERP' do
    budget = revision.start(company: 'somosemp', number: 4119)
    Outsider::Erp::BudgetForm.new(budget, settings).apply('items' => [])

    expect(revision.cancel(budget)).to be_imported
    expect(budget.reload.revision).to be_nil
    expect(erp.writes_made).to be_empty
  end
end
