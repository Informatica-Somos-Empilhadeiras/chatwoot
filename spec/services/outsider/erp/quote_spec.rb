require 'rails_helper'

# OUTSIDER: criação do orçamento no ERP a partir de uma proposta do CRM (QuoteBuilder monta a SQL, Catalog confere os
# produtos, QuoteCreator orquestra pelo query_execute). O ERP é simulado: o PUT /dashboard/api/query_execute devolve
# conforme a SQL recebida. Nenhuma chamada real sai nos testes.
RSpec.describe 'Outsider ERP quotes' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:base) { 'https://somos-backend.inntegra.com.br' }
  let(:settings) { Outsider::Erp::Settings.new(account) }
  let(:contact) { create(:contact, account: account, name: 'GDS Ltda') }
  let(:product) { crm_product(account, erp_codigo_produto: 1234) }
  let(:proposal) do
    crm_proposal(
      account, owner: user, contact: contact,
               items: [{ description: 'Empilhadeira', quantity: 2, unit_price_cents: 10_000_000, discount_cents: 500_000, product: product },
                       { description: 'Frete', quantity: 1, unit_price_cents: 50_000 }]
    )
  end

  # responde o query_execute conforme a SQL (números fixos para conferir o resultado)
  def stub_query(present_codes: [1234], number: 5001, items_count: 0)
    stub_request(:put, "#{base}/dashboard/api/query_execute").to_return do |request|
      sql = JSON.parse(request.body)['SQL_Execute']
      body =
        if sql.include?('sp_CadastraOrcamento') then [{ 'codigo' => number }]
        elsif sql.include?('sp_CadastraItemOrcamento') then [{ 'codigo' => 1 }]
        elsif sql.include?('sp_FinalizaOrcamento') then [{ 'resultado' => 'OK' }]
        elsif sql.include?('detalheorcamento') then [{ 'n' => items_count }]
        elsif sql.include?('CodigoProduto IN') then present_codes.map { |code| { 'CodigoProduto' => code } }
        else
          []
        end
      { status: 200, body: body.to_json }
    end
  end

  before do
    settings.update('enabled' => true, 'companies' => %w[somosemp somosfilial], 'device_id' => 'abc',
                    'quote_write_enabled' => true, 'quote_forma_pagto' => 3)
    Outsider::Erp::ContactLink.new(contact).add(company: 'somosemp', code: 716, name: 'GDS', settings: settings)
  end

  describe Outsider::Erp::QuoteBuilder do
    subject(:builder) do
      described_class.new(proposal: proposal, settings: settings, company: 'somosemp', codigo_cliente: 716, vendedor_erp_id: '0')
    end

    it 'splits items by ERP product link' do
      expect(builder.sellable_items.map(&:description)).to eq(['Empilhadeira'])
      expect(builder.skipped_items.map(&:description)).to eq(['Frete'])
    end

    it 'builds bank-prefixed, idempotent SQL using the ERP functions' do
      expect(builder.header_sql).to start_with('SELECT somosemp.sp_CadastraOrcamento(')
      expect(builder.header_sql).to include("'CW-#{proposal.id}'")
      item_sql = builder.item_sql(5001, builder.sellable_items.first)
      # orçamento, produto, quantidade, valor em reais, desconto %, total em reais
      expect(item_sql).to include('somosemp.sp_CadastraItemOrcamento(5001, 1234, 2.0, 100000.0, 2.5, 195000.0,')
      expect(builder.finalize_sql(5001)).to eq('SELECT somosemp.sp_FinalizaOrcamento(5001) AS resultado')
    end
  end

  describe Outsider::Erp::Lists do
    it 'reads the Kanban support lists with the configured companies' do
      Rails.cache.clear
      list = stub_request(:get, "#{base}/KanbanOrdemServico/api/ListaTecnicos")
             .with(query: { 'listaEmpresas' => %w[somosemp somosfilial] })
             .to_return(status: 200, body: [{ 'Codigo' => 12, 'Nome' => 'CARLOS' }, { 'Nome' => 'sem codigo' }].to_json)
      lists = described_class.new(account)

      expect(lists.technicians).to eq([{ codigo: 12, nome: 'CARLOS' }])
      expect(list).to have_been_made.once
    end
  end

  describe Outsider::Erp::Catalog do
    subject(:catalog) { described_class.new(account) }

    it 'searches products scoped to a configured company' do
      stub_request(:put, "#{base}/dashboard/api/query_execute")
        .to_return(status: 200, body: [{ 'CodigoProduto' => 1234, 'Descricao' => 'EMPILHADEIRA' }].to_json)
      expect(catalog.search('somosemp', 'empil')).to eq([{ codigo: 1234, descricao: 'EMPILHADEIRA' }])
      expect { catalog.search('outra', 'empil') }.to raise_error(ArgumentError)
    end

    it 'reports which codes exist in the bank' do
      stub_query(present_codes: [1234])
      expect(catalog.existing_codes('somosemp', [1234, 9999])).to eq([1234])
    end
  end

  describe Outsider::Erp::QuoteCreator do
    subject(:creator) { described_class.new(account: account, user: user, proposal: proposal) }

    it 'creates the quote and stores the number on the proposal, listing the free item as skipped' do
      stub_query
      result = creator.call

      expect(result).to have_attributes(number: 5001, company: 'somosemp', skipped: ['Frete'], already: false)
      expect(proposal.reload).to have_attributes(erp_quote_number: 5001, erp_company: 'somosemp')
      expect(proposal.erp_synced_at).to be_present
    end

    it 'is idempotent: a synced proposal returns the existing number without calling the ERP' do
      proposal.update_columns(erp_quote_number: 4000, erp_company: 'somosemp') # rubocop:disable Rails/SkipsModelValidations
      result = creator.call
      expect(result).to have_attributes(number: 4000, already: true)
      expect(a_request(:put, %r{/dashboard/api/query_execute})).not_to have_been_made
    end

    it 'leaves out a mapped product that does not exist in the bank' do
      stub_query(present_codes: []) # 1234 não existe nessa unidade
      expect { creator.call }.to raise_error(Outsider::Erp::QuoteCreator::Invalid, 'sem_itens')
    end

    it 'refuses when quote writing is off or the payment method is unset' do
      settings.update('quote_write_enabled' => false)
      expect { described_class.new(account: account, user: user, proposal: proposal).call }
        .to raise_error(Outsider::Erp::QuoteCreator::Disabled)

      settings.update('quote_write_enabled' => true, 'quote_forma_pagto' => 0)
      expect { described_class.new(account: account, user: user, proposal: proposal).call }
        .to raise_error(Outsider::Erp::QuoteCreator::Invalid, 'forma_pagto')
    end

    it 'refuses when the contact is not linked to an ERP customer' do
      Outsider::Erp::ContactLink.new(contact).remove(company: 'somosemp', code: 716)
      expect { creator.call }.to raise_error(Outsider::Erp::QuoteCreator::Invalid, 'sem_cliente')
    end

    it 'asks which company when the contact has customers in more than one, then uses the chosen one' do
      Outsider::Erp::ContactLink.new(contact).add(company: 'somosfilial', code: 99, name: 'GDS', settings: settings)
      expect { creator.call }.to raise_error(Outsider::Erp::QuoteCreator::Invalid, 'ambiguo:somosemp,somosfilial')

      stub_query
      result = described_class.new(account: account, user: user, proposal: proposal, company: 'somosfilial').call
      expect(result.company).to eq('somosfilial')
      expect(a_request(:put, %r{/dashboard/api/query_execute}).with { |req| req.body.include?('somosfilial.sp_CadastraOrcamento(99,') })
        .to have_been_made
    end
  end
end
