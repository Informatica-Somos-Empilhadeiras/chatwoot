require 'rails_helper'

RSpec.describe Outsider::Crm::ProposalPdf do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator, name: 'Vendedora') }

  # O projeto não tem leitor de PDF em Ruby: usa o pdftotext (poppler) quando a máquina tem
  def pdf_text(data)
    skip 'pdftotext não instalado' unless system('which pdftotext > /dev/null 2>&1')
    Open3.capture2('pdftotext', '-layout', '-', '-', stdin_data: data, binmode: true).first.force_encoding('UTF-8')
  end

  def page_count(data)
    data.scan(%r{/Type /Page\b}).size
  end

  before do
    Outsider::Crm::ProposalConfig.new(account).update_company({ legal_name: 'Empresa Exemplo Ltda', cnpj: '00.000.000/0001-00',
                                                                city: 'Goiânia', bank_details: 'Banco Exemplo - Ag 0001' })
  end

  it 'renders a sale proposal with the default letterhead, the machine and the conditions' do
    product = crm_product(account)
    product.image.attach(io: Rails.root.join('spec/assets/sample.png').open, filename: 'sample.png', content_type: 'image/png')
    proposal = crm_proposal(account, owner: user, items: [{ description: product.name, product: product, quantity: 1,
                                                            unit_price_cents: 15_000_000, show_details: true, details: product.details }],
                                     customer: { 'company' => 'Cliente **Exemplo** Ltda', 'document' => '11.111.111/0001-11', 'attention' => 'Ana' })

    document = described_class.new(proposal.reload)
    data = document.render
    text = pdf_text(data)

    expect(data).to start_with('%PDF')
    expect(document.filename).to eq("PROPOSTA #{proposal.number} - CLIENTE EXEMPLO LTDA.pdf")
    expect(text).to include('PROPOSTA', proposal.number.to_s, 'Capacidade de carga', '3500 kg', 'EQUIPAMENTO', 'R$ 150.000,00')
    expect(text).to include('Goiânia', 'Banco Exemplo')
    expect(page_count(data)).to be >= 3
  end

  it 'renders a rental proposal with the conditions as a list and the parties' do
    proposal = crm_proposal(account, owner: user, kind: :rental)

    text = pdf_text(described_class.new(proposal).render)

    expect(text).to include('PROPOSTA', proposal.number.to_s)
    expect(text).to include('Empresa Exemplo Ltda')
  end

  it 'keeps asterisks that are not bold markers and drops characters the font cannot draw' do
    proposal = crm_proposal(account, owner: user, notes: 'Frete por conta do cliente, se houver** 🚜 obrigado')

    text = pdf_text(described_class.new(proposal).render)

    expect(text).to include('se houver**')
    expect(text).not_to include('🚜')
  end
end
