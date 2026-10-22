# OUTSIDER: monta o PDF da proposta (A4) com o Prawn, seguindo o modelo (Outsider::Crm::ProposalTemplateLayout):
# os blocos do conteúdo em sequência (data e número, cliente, abertura, título, características das máquinas,
# itens, condições, partes, fechamento, dados bancários, assinatura, observações e textos livres) e, por cima,
# o papel timbrado: cabeçalho, rodapé e os elementos em posição livre, em todas as páginas ou só na primeira.
# Sem desenho próprio, o modelo segue o das propostas da Somos (Entrega 14). Papel timbrado padrão em
# config/outsider_crm. Fontes do próprio PDF (Helvetica, Times, Courier): caracteres fora do português comum
# (emoji, por exemplo) saem do texto.
class Outsider::Crm::ProposalPdf
  include Outsider::Crm::ProposalPdf::Text
  include Outsider::Crm::ProposalPdf::Letterhead
  include Outsider::Crm::ProposalPdf::Machines
  include Outsider::Crm::ProposalPdf::ItemsPage
  include Outsider::Crm::ProposalPdf::ClosingPage

  FONT_SIZE = 9
  MM = 72 / 25.4
  HIGHLIGHT = 'FFFF00'.freeze
  BLUE = '1F3A93'.freeze
  DEFAULT_HEADER = Rails.root.join('config/outsider_crm/proposta-cabecalho.jpg')
  DEFAULT_FOOTER = Rails.root.join('config/outsider_crm/proposta-rodape.jpg')
  # espaço antes de cada bloco (pt) quando ele vem depois de outro na mesma página
  SPACE_BEFORE = { 'customer' => 14, 'intro' => 10, 'title' => 12, 'specs' => 12, 'conditions' => 28, 'parties' => 24,
                   'closing' => 8, 'bank' => 24, 'signature' => 30, 'notes' => 24 }.freeze
  # e quando abre uma página nova, depois da linha com o número da proposta
  SPACE_ON_NEW_PAGE = { 'items' => 0, 'bank' => 24 }.freeze
  BLOCKS = {
    'date_number' => :date_number_block, 'customer' => :customer_block, 'intro' => :intro_block, 'title' => :title_block,
    'specs' => :machines_block, 'items' => :items_block, 'conditions' => :conditions_block, 'parties' => :parties_block,
    'closing' => :closing_block, 'bank' => :bank_block, 'signature' => :signature_block, 'notes' => :notes_block,
    'text' => :text_block
  }.freeze

  # O texto já sai limpo para Windows-1252 (clean), então o aviso do Prawn sobre fontes embutidas não ajuda
  Prawn::Fonts::AFM.hide_m17n_warning = true

  # template: modelo ainda não salvo, para a pré-visualização do editor
  def initialize(proposal, template: nil)
    @proposal = proposal
    @template = template || proposal.template
    @layout = @template.layout
    @company = Outsider::Crm::ProposalConfig.new(proposal.account).company(proposal.business_unit_id)
    @fields = Outsider::Crm::ProposalFields.new(proposal, @company)
  end

  def filename
    customer = @proposal.customer['company'].to_s.parameterize(separator: ' ').upcase.first(60)
    "PROPOSTA #{@proposal.number} - #{customer}.pdf".squeeze(' ')
  end

  def render
    prepare_letterhead
    @pdf = Prawn::Document.new(page_size: 'A4', margin: first_page_margins,
                               info: { Title: clean(filename.delete_suffix('.pdf')), Creator: 'CRM' })
    keep_margins_on_new_pages
    @pdf.font(@layout['font'], size: FONT_SIZE)
    @pdf.default_leading = 1
    @blank_page = true
    @template.blocks.each { |block| render_block(block) if block['visible'] }
    draw_letterhead
    @pdf.render
  end

  private

  def render_block(block)
    if block['new_page'] && !@blank_page
      @pdf.start_new_page
      proposal_number_line
      @pdf.move_down SPACE_ON_NEW_PAGE.fetch(block['type'], 12)
    elsif !@blank_page
      @pdf.move_down SPACE_BEFORE.fetch(block['type'], 12)
    end
    page = @pdf.page_number
    with_block_style(block) { send(BLOCKS.fetch(block['type']), block) }
    @blank_page = false if @pdf.page_number != page || @pdf.cursor < @pdf.bounds.top
  end

  def proposal_number_line
    write(fragments("<b>PROPOSTA</b>  <b>#{@proposal.number}</b>"), align: :right)
    @pdf.move_down 2
  end

  # ---------- blocos da abertura ----------

  def date_number_block(_block)
    top = @pdf.cursor
    say(@fields.date_line)
    @pdf.move_cursor_to(top)
    write(fragments("<b>PROPOSTA</b>  #{@proposal.number}"), align: :right)
  end

  def customer_block(_block)
    customer = @proposal.customer
    [label_line('EMPRESA', customer['company']), document_line(customer), label_line('ENDEREÇO', customer['address']),
     place_line(customer), label_line('FONE', customer['phone']), label_line('E-MAIL', customer['email'])]
      .each { |line| write(fragments(line)) }
    @pdf.move_down 10
    say("Atenção: #{customer['attention']}") if customer['attention'].present?
  end

  def document_line(customer)
    line = label_line('CNPJ', customer['document'])
    customer['state_registration'].present? ? "#{line} - #{label_line('IE', customer['state_registration'])}" : line
  end

  def place_line(customer)
    [label_line('BAIRRO', customer['district']), label_line('CIDADE', customer['city']),
     label_line('ESTADO', customer['state']), label_line('CEP', customer['zip'])].join(' - ')
  end

  def label_line(label, value)
    "#{label}: <b>#{escape(value)}</b>"
  end

  def intro_block(_block)
    rich(@template.text(:intro)) if @template.text(:intro).present?
  end

  def title_block(_block)
    say([@template.text(:title_prefix), @proposal.title].compact_blank.join(' '), bold: true)
  end

  # Texto livre do modelo, com título opcional
  def text_block(block)
    if block['heading'].present?
      say(@fields.apply(block['heading']), bold: true, size: block['size'] + 1)
      @pdf.move_down 6
    end
    rich(block['text'], align: :justify) if block['text'].present?
  end
end
