require 'rails_helper'

# OUTSIDER: orçamento de peças e serviços feito no chat (Outsider::Erp::Budget): rascunho, gravação no ERP pelas
# funções do Mais Prático (retomável), PDF no modelo do relatório e cópia. O ERP é o OutsiderFakeErp (spec/support).
RSpec.describe 'Outsider ERP parts and services budget' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:settings) { Outsider::Erp::Settings.new(account) }
  let(:contact) { create(:contact, account: account, name: 'Gilmar Souza', email: 'gilmar@alvorada.com.br') }
  let!(:erp) { stub_fake_erp }
  let(:items) do
    [{ 'codigo' => 923, 'descricao' => 'TIMAO', 'quantidade' => 1, 'preco' => '3.181,47', 'desconto' => 0 },
     { 'codigo' => 491, 'descricao' => 'MOLA GAS', 'quantidade' => 1, 'preco' => 142, 'desconto' => 10 },
     { 'codigo' => 503, 'descricao' => 'HORA TECNICA', 'tipo' => 1, 'quantidade' => 2, 'preco' => 250, 'desconto' => 0 }]
  end
  let(:budget) do
    draft = Outsider::Erp::BudgetDefaults.new(account, user).build(contact: contact)
    Outsider::Erp::BudgetForm.new(draft, settings).apply('items' => items, 'terms' => { 'vendedor' => 7, 'prazo_entrega' => '5 dias úteis' })
  end

  before do
    settings.update('enabled' => true, 'companies' => %w[somosemp somosfilial], 'device_id' => 'abc', 'quote_write_enabled' => true,
                    'quote_forma_pagto' => 3, 'quote_validade' => '10 dias', 'quote_discount_approval' => false)
    Outsider::Erp::ContactLink.new(contact).add(company: 'somosemp', code: 716, name: 'SUPERMERCADO ALVORADA', settings: settings)
  end

  describe Outsider::Erp::BudgetDefaults do
    it 'opens a draft with the linked customer, the contact as A/C and the default conditions' do
      draft = described_class.new(account, user).build(contact: contact)

      expect(draft).to have_attributes(status: 'draft', company: 'somosemp', customer_code: 716, customer_name: 'SUPERMERCADO ALVORADA')
      expect(draft.terms).to include('forma_pagto' => 3, 'contato' => 'Gilmar Souza', 'validade' => '10 dias')
      expect(draft.terms).not_to have_key('vendedor')
    end

    it 'remembers the seller this person picked last time' do
      budget
      expect(described_class.new(account, user).build(contact: contact).terms['vendedor']).to eq(7)
    end
  end

  describe Outsider::Erp::BudgetForm do
    it 'cleans items: Brazilian decimals, discount as %, service type, unknown codes dropped' do
      expect(budget.items.pluck('preco')).to eq([3181.47, 142.0, 250.0])
      expect(budget.items.pluck('tipo')).to eq([0, 0, 1])
      expect(budget.total.to_f).to eq(3181.47 + 127.8 + 500)

      described_class.new(budget, settings).apply('items' => [{ 'codigo' => 'x' }, { 'codigo' => 491, 'desconto' => 150 }])
      expect(budget.items).to contain_exactly(include('codigo' => 491, 'desconto' => 100.0, 'quantidade' => 1.0))
    end

    it 'only accepts a company from the settings and refuses to change a recorded budget' do
      form = described_class.new(budget, settings)
      expect { form.apply('company' => 'outrobanco', 'customer_code' => 1) }.to raise_error(Outsider::Erp::BudgetForm::Invalid, 'company')

      budget.update!(erp_number: 5001)
      expect { form.apply('terms' => { 'contato' => 'x' }) }.to raise_error(Outsider::Erp::BudgetForm::Invalid, 'in_erp')
    end
  end

  describe Outsider::Erp::QuoteCreator do
    subject(:creator) { described_class.new(budget, user: user) }

    it 'records header, parts, conditions guarded by the chat key, and leaves the service out while direct writing is off' do
      settings.update('quote_services_direct' => false)
      creator.call

      expect(budget.reload).to have_attributes(status: 'created', erp_number: 5001)
      expect(erp.lines).to eq([923, 491])
      expect(budget.erp_result['skipped']).to eq([{ 'codigo' => 503, 'descricao' => 'HORA TECNICA', 'motivo' => 'servico' }])
      expect(erp.sqls.grep(/sp_CadastraOrcamento/).first).to start_with('SELECT somosemp.sp_CadastraOrcamento(716, ')
      update = erp.sqls.grep(/\AUPDATE/).first
      expect(update).to include("O.`PrazoEntrega` = '5 dias úteis'", "O.`Validade` = '10 dias'",
                                "WHERE O.codigoorcamento = 5001 AND O.CodigoIntegracaoMobile = 'CWO-#{budget.id}'")
    end

    it 'writes the service line directly (the default), only for a service product of this budget' do
      creator.call

      expect(erp.lines).to eq([923, 491, 503])
      insert = erp.sqls.grep(/\AINSERT INTO/).first
      expect(insert).to include('somosemp.detalheorcamento', 'P.Tipo = 1', "O.CodigoIntegracaoMobile = 'CWO-#{budget.id}'")
      expect(erp.sqls.grep(/\AUPDATE/).first).to include('O.`totalServicos` = 500.0')
    end

    it 'writes directly, without tax, a part the ERP function dropped (no NCM for the customer state)' do
      erp.drop = [491]
      creator.call

      expect(erp.lines).to eq([923, 503, 491])
      direct = erp.sqls.grep(/\AINSERT INTO/).find { |sql| sql.include?('P.CodigoProduto = 491') }
      expect(direct).to include("O.CodigoIntegracaoMobile = 'CWO-#{budget.id}'")
      expect(direct).not_to include('P.Tipo = 1')
      expect(budget.reload.erp_result['skipped']).to be_empty
      expect(erp.sqls.index(direct)).to be < erp.sqls.index(erp.sqls.grep(/sp_FinalizaOrcamento/).first)
    end

    it 'reports a dropped part when writing parts directly is off' do
      settings.update('quote_parts_direct' => false)
      erp.drop = [491]
      creator.call
      expect(erp.lines).to eq([923, 503])
      expect(budget.reload.erp_result['skipped']).to include(include('codigo' => 491, 'motivo' => 'ncm'))
    end

    it 'always records REVENDA as the operation gender' do
      Outsider::Erp::BudgetForm.new(budget, settings).apply('terms' => budget.terms.merge('genero' => 7))
      expect(budget.terms['genero']).to eq(1)
      budget.update!(terms: budget.terms.merge('genero' => 5))

      creator.call
      expect(erp.sqls.grep(/sp_CadastraOrcamento/).first).to include(', 7, 0, 0, 1, ')
    end

    it 'resumes after the ERP fails mid-way without repeating the header or the lines already in' do
      erp.fail_on_item = 491
      expect { creator.call }.to raise_error(Outsider::Erp::Client::Error)
      expect(budget.reload).to have_attributes(status: 'draft', erp_number: 5001)

      described_class.new(budget.reload, user: user).call
      expect(erp.lines).to eq([923, 491, 503])
      expect(erp.sqls.grep(/sp_CadastraOrcamento/).size).to eq(1)
      expect(budget.reload.status).to eq('created')
    end

    it 'refuses while quote writing is off or without seller' do
      settings.update('quote_write_enabled' => false)
      expect { described_class.new(budget, user: user).call }.to raise_error(Outsider::Erp::QuoteCreator::Disabled)

      settings.update('quote_write_enabled' => true)
      budget.update!(terms: budget.terms.except('vendedor'))
      expect { described_class.new(budget, user: user).call }.to raise_error(Outsider::Erp::QuoteCreator::Invalid, 'vendedor')
      expect(erp.writes_made).to be_empty
    end
  end

  describe Outsider::Erp::DiscountPolicy do
    subject(:policy) { described_class.new(budget, settings) }

    before { settings.update('quote_discount_approval' => true, 'quote_discount_line_max' => 5, 'quote_discount_total_max' => 5) }

    it 'asks for approval above the line limit and blocks recording until approved' do
      expect(policy.over_lines).to eq(['491'])
      expect(policy).to be_blocked
      expect { Outsider::Erp::QuoteCreator.new(budget, user: user).call }
        .to raise_error(Outsider::Erp::QuoteCreator::Invalid, 'desconto_sem_liberacao')

      policy.grant(code: 7, name: 'CRISTIANE', user: user)
      expect(policy).not_to be_blocked
      expect(policy.as_json).to include(approved: true, approved_by: 'CRISTIANE')
    end

    it 'keeps the approval when the discount goes down and asks again when it goes up or moves to another product' do
      policy.grant(code: 7, name: 'CRISTIANE', user: user)
      form = Outsider::Erp::BudgetForm.new(budget, settings)

      form.apply('items' => items.map { |item| item['codigo'] == 491 ? item.merge('desconto' => 8) : item })
      expect(described_class.new(budget, settings)).not_to be_blocked
      form.apply('items' => items.map { |item| item['codigo'] == 491 ? item.merge('desconto' => 12) : item })
      expect(described_class.new(budget, settings)).to be_blocked
      form.apply('items' => items.map { |item| item.merge('desconto' => item['codigo'] == 923 ? 10 : 0) })
      expect(described_class.new(budget, settings)).to be_blocked
    end

    it 'writes who approved on the ERP quote, guarded by the chat key' do
      policy.grant(code: 7, name: 'CRISTIANE', user: user)
      Outsider::Erp::QuoteCreator.new(budget, user: user).call

      update = erp.sqls.grep(/\AUPDATE /).last
      expect(update).to include('O.`AutorizadoPor` = 7', 'O.`DataAutorizadoPor` = NOW()', "CodigoIntegracaoMobile = 'CWO-#{budget.id}'")
    end
  end

  describe Outsider::Erp::DiscountApprover do
    subject(:approver) { described_class.new(account_user) }

    let(:account_user) { account.account_users.find_by(user: user) }

    it 'accepts a manager or someone with the ERP discount permission, sending only the MD5 of the password' do
      expect(approver.verify('somosemp', '7', 'segredo')).to eq(code: 7, name: 'CRISTIANE')
      expect(approver.verify('somosemp', 12, 'segredo')).to eq(code: 12, name: 'CARLOS')
      expect(erp.sqls.join).not_to include('segredo')
      expect(erp.sqls.grep(/funcionarios L/).map { |sql| sql[/\ASELECT (.*?) FROM/, 1] }.join).not_to include('Senha')
    end

    it 'refuses a wrong password, someone without permission, and locks after too many tries' do
      expect { approver.verify('somosemp', 30, 'segredo') }.to raise_error(described_class::Refused, 'sem_permissao')
      expect { approver.verify('somosemp', 7, 'errada') }.to raise_error(described_class::Refused, 'senha_invalida')
      4.times { expect { approver.verify('somosemp', 7, 'errada') }.to raise_error(described_class::Refused) }
      expect { approver.verify('somosemp', 7, 'segredo') }.to raise_error(described_class::Refused, 'tentativas')
      expect { approver.verify('outrobanco', 7, 'segredo') }.to raise_error(ArgumentError)
    end
  end

  describe Outsider::Erp::QuotePdf do
    it 'renders the recorded quote in the ERP report layout' do
      report = Outsider::Erp::QuoteReport.new(account).build('somosemp', 3310)
      pdf = described_class.new(report)

      expect(report).to include('numero' => 3310, 'vendedor' => 'CRISTIANE', 'pagamento' => '28/56/84 DIAS')
      expect(report['itens'].second).to include('desconto' => 14.2, 'total' => 127.8)
      expect(pdf.filename).to eq('ORCAMENTO 3310 - SUPERMERCADO ALVORADA GOIANO LTDA.pdf')
      expect(pdf.render).to start_with('%PDF')
      expect(erp.writes_made).to be_empty
    end

    it 'renders the draft preview with a watermark name' do
      pdf = described_class.new(Outsider::Erp::BudgetPreview.new(budget).build)
      expect(pdf.filename).to start_with('PREVIA ORCAMENTO')
      expect(pdf.render).to start_with('%PDF')
    end
  end

  describe Outsider::Erp::BudgetCopy do
    it 'copies a quote made in the ERP: lines with type and discount %, conditions and payment code' do
      imported = Outsider::Erp::BudgetImporter.new(account, user).import(company: 'somosemp', number: 3310, contact: contact)
      copy = described_class.new(account).from(imported)
      draft = Outsider::Erp::BudgetDefaults.new(account, user).build(contact: contact, copy: copy)

      expect(imported).to have_attributes(status: 'imported', customer_code: 716)
      expect(draft.items.map { |item| item.values_at('codigo', 'tipo', 'desconto') }).to eq([[923, 0, 0.0], [491, 0, 10.0], [503, 1, 0.0]])
      expect(draft.terms).to include('forma_pagto' => 3, 'prazo_entrega' => '5 dias úteis', 'observacoes' => 'TIMAO MODELO CBD')
    end

    it 'imports the same ERP quote only once' do
      importer = Outsider::Erp::BudgetImporter.new(account, user)
      first = importer.import(company: 'somosemp', number: 3310, contact: contact)
      expect(importer.import(company: 'somosemp', number: '3310', contact: contact)).to eq(first)
      expect { importer.import(company: 'outro', number: 1, contact: contact) }.to raise_error(Outsider::Erp::BudgetImporter::Invalid)
    end
  end

  describe Outsider::Erp::BudgetSender do
    let(:account_user) { account.account_users.find_by(user: user) }

    before { budget.update!(status: :created, erp_number: 3310) }

    it 'emails the PDF to several addresses with subject and body, and keeps the send' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('SMTP_ADDRESS').and_return('smtp.example.com')
      record = described_class.new(account_user).deliver(budget, channel: 'email', to: ['compras@alvorada.com.br; nf@alvorada.com.br'],
                                                                 subject: 'Orçamento Nº 3310', message: 'Segue.')

      expect(record).to have_attributes(channel: 'email', recipients: %w[compras@alvorada.com.br nf@alvorada.com.br], status: 'pending')
      expect(record.document).to be_attached
      expect(Outsider::Erp::BudgetMailJob).to have_been_enqueued.with(record.id, 'Orçamento Nº 3310', 'Segue.')
    end

    it 'blocks bad addresses, missing subject and a draft' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('SMTP_ADDRESS').and_return('smtp.example.com')
      sender = described_class.new(account_user)
      expect { sender.deliver(budget, channel: 'email', to: ['x@'], subject: 'a') }.to raise_error(described_class::Blocked, 'invalid_email')
      expect { sender.deliver(budget, channel: 'email', to: ['a@b.com'], subject: '') }.to raise_error(described_class::Blocked, 'subject_required')

      budget.update!(erp_number: nil, status: :draft)
      expect { sender.deliver(budget, channel: 'email', to: ['a@b.com'], subject: 'a') }.to raise_error(described_class::Blocked, 'not_in_erp')
    end
  end

  describe Outsider::Erp::Catalog do
    it 'tells parts from services among the codes that exist in the bank' do
      expect(described_class.new(account).kinds('somosemp', [491, 503, 9999])).to eq(491 => 0, 503 => 1)
      expect { described_class.new(account).kinds('outrobanco', [1]) }.to raise_error(ArgumentError)
    end
  end

  describe Outsider::Erp::Lists do
    it 'reads the Kanban support lists with the configured companies' do
      Rails.cache.clear
      list = stub_request(:get, %r{/KanbanOrdemServico/api/ListaTecnicos})
             .with(query: { 'listaEmpresas' => %w[somosemp somosfilial] })
             .to_return(status: 200, body: [{ 'Codigo' => 12, 'Nome' => 'CARLOS' }, { 'Nome' => 'sem codigo' }].to_json)

      expect(described_class.new(account).technicians).to eq([{ codigo: 12, nome: 'CARLOS' }])
      expect(list).to have_been_made.once
    end
  end
end
