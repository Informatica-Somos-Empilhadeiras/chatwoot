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

  describe 'template design (blocks and letterhead)' do
    let(:proposal) { crm_proposal(account, owner: user, customer: { 'company' => 'Cliente Exemplo Ltda', 'phone' => '(62) 1234-5678' }) }
    let(:template) { proposal.template }

    def design(blocks: template.blocks, layout: {})
      template.update!(content: template.content.merge('blocks' => blocks, 'layout' => layout))
      described_class.new(proposal.reload).render
    end

    it 'follows the block order, hides blocks and renders free texts with fields' do
      blocks = template.blocks.map { |block| block['type'] == 'customer' ? block.merge('visible' => false) : block }
      free = { 'type' => 'text', 'heading' => 'Garantia {proposta.numero}', 'text' => 'Garantia **total** para =={cliente.empresa}==',
               'highlight' => true, 'size' => 11 }
      blocks.insert(blocks.index { |block| block['type'] == 'items' }, free.merge('new_page' => true))

      text = pdf_text(design(blocks: blocks))

      expect(text).not_to include('(62) 1234-5678')
      expect(text).to include("Garantia #{proposal.number}", 'Garantia total para Cliente Exemplo Ltda')
      expect(text.index('Garantia total')).to be < text.index('Descrição')
    end

    it 'draws free elements on every page or only on the first' do
      layout = { 'font' => 'Times-Roman', 'header_pages' => 'first',
                 'elements' => [{ 'type' => 'text', 'x' => 120, 'y' => 30, 'width' => 80, 'text' => 'Contato: {proposta.numero}', 'pages' => 'all' },
                                { 'type' => 'text', 'x' => 20, 'y' => 30, 'width' => 80, 'text' => 'Selo da primeira', 'pages' => 'first' }] }

      data = design(layout: layout)
      text = pdf_text(data)

      expect(text.scan("Contato: #{proposal.number}").size).to eq(page_count(data))
      expect(text.scan('Selo da primeira').size).to eq(1)
    end

    it 'draws an image element from the template images' do
      template.layout_images.attach(io: Rails.root.join('spec/assets/sample.png').open, filename: 'selo.png', content_type: 'image/png')
      image_id = template.layout_images.attachments.first.id
      plain = design(layout: {})

      with_image = design(layout: { 'elements' => [{ 'type' => 'image', 'x' => 10, 'y' => 250, 'width' => 30, 'image_id' => image_id }] })

      expect(with_image.bytesize).to be > plain.bytesize
    end
  end
end
