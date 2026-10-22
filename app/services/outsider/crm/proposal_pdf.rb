# OUTSIDER: monta o PDF da proposta (A4) com o Prawn, no desenho das propostas da Somos:
#   1ª página: data e número, dados do cliente, abertura, título, principais características com a imagem
#              da máquina e a lista do equipamento;
#   depois:    itens e total, condições (quadro na venda, lista na locação) e, na locação, as partes;
#   última:    confirmação de pedido, dados bancários, para onde mandar a documentação e as assinaturas.
# Papel timbrado (cabeçalho e rodapé) em todas as páginas: o do modelo ou, nos modelos padrão, o que vem
# com o CRM (config/outsider_crm). Fonte Helvetica do próprio PDF: caracteres fora do português comum
# (emoji, por exemplo) saem do texto.
class Outsider::Crm::ProposalPdf
  include Outsider::Crm::ProposalPdf::ItemsPage
  include Outsider::Crm::ProposalPdf::ClosingPage
  include Outsider::Crm::ProposalPdf::Text

  MARGIN_X = 36
  FONT_SIZE = 9
  HIGHLIGHT = 'FFFF00'.freeze
  BLUE = '1F3A93'.freeze
  DEFAULT_HEADER = Rails.root.join('config/outsider_crm/proposta-cabecalho.jpg')
  DEFAULT_FOOTER = Rails.root.join('config/outsider_crm/proposta-rodape.jpg')

  # O texto já sai limpo para Windows-1252 (clean), então o aviso do Prawn sobre fontes embutidas não ajuda
  Prawn::Fonts::AFM.hide_m17n_warning = true

  def initialize(proposal)
    @proposal = proposal
    @template = proposal.template
    @company = Outsider::Crm::ProposalConfig.new(proposal.account).company(proposal.business_unit_id)
    @fields = Outsider::Crm::ProposalFields.new(proposal, @company)
  end

  def filename
    customer = @proposal.customer['company'].to_s.parameterize(separator: ' ').upcase.first(60)
    "PROPOSTA #{@proposal.number} - #{customer}.pdf".squeeze(' ')
  end

  def render
    header = image_data(@template.header_image, DEFAULT_HEADER)
    footer = image_data(@template.footer_image, DEFAULT_FOOTER)
    @header_height = letterhead_height(header)
    @footer_height = letterhead_height(footer)
    @pdf = Prawn::Document.new(page_size: 'A4', margin: [@header_height + 18, MARGIN_X, @footer_height + 22, MARGIN_X],
                               info: { Title: clean(filename.delete_suffix('.pdf')), Creator: 'CRM' })
    @pdf.font('Helvetica', size: FONT_SIZE)
    @pdf.default_leading = 1
    first_page
    items_page
    closing_page
    letterhead(header, footer)
    @pdf.render
  end

  private

  # ---------- 1ª página ----------

  def first_page
    date_and_number(@fields.date_line)
    @pdf.move_down 14
    customer_block
    @pdf.move_down 10
    attention = @proposal.customer['attention']
    @pdf.text("Atenção: #{clean(attention)}") if attention.present?
    @pdf.move_down 10
    rich(@template.text(:intro)) if @template.text(:intro).present?
    @pdf.move_down 12
    title = [@template.text(:title_prefix), @proposal.title].compact_blank.join(' ')
    @pdf.text(clean(title), style: :bold, size: 10)
    @pdf.move_down 12
    machine_details if @template.flag?(:show_specs)
  end

  def date_and_number(left)
    top = @pdf.cursor
    @pdf.text(clean(left))
    @pdf.move_cursor_to(top)
    @pdf.text("<b>PROPOSTA</b>  #{@proposal.number}", inline_format: true, align: :right)
  end

  def customer_block
    customer = @proposal.customer
    [label_line('EMPRESA', customer['company']), document_line(customer), label_line('ENDEREÇO', customer['address']),
     place_line(customer), label_line('FONE', customer['phone']), label_line('E-MAIL', customer['email'])]
      .each { |line| @pdf.text(line, inline_format: true) }
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

  def machine_details
    detailed = @proposal.items.select { |item| item.show_details && item.details.present? }
    detailed.each_with_index do |item, index|
      @pdf.move_down 10 if index.positive?
      @pdf.text(clean(item.description), style: :bold) if detailed.size > 1
      specs_with_image(item)
      features(item.details['features'])
    end
  end

  def specs_with_image(item)
    specs = Array(item.details['specs'])
    image = item.image
    return if specs.empty? && image.nil?

    @pdf.text('Principais Características', style: :bold, size: 10)
    @pdf.move_down 16
    top = @pdf.cursor
    left_width = image ? @pdf.bounds.width * 0.6 : @pdf.bounds.width
    @pdf.bounding_box([0, top], width: left_width) { specs_table(specs) } if specs.any?
    after_specs = @pdf.cursor
    after_image = image ? product_image(image, top, left_width) : after_specs
    @pdf.move_cursor_to([after_specs, after_image].min)
    @pdf.move_down 14
  end

  def specs_table(specs)
    rows = specs.map do |spec|
      style = spec['bold'] ? :bold : :normal
      [{ content: clean(spec['label']), font_style: style }, { content: clean(spec['value']), font_style: style }]
    end
    @pdf.table(rows, width: @pdf.bounds.width, column_widths: { 1 => @pdf.bounds.width * 0.3 },
                     cell_style: { borders: [], padding: [0.5, 2], size: FONT_SIZE })
  end

  def product_image(image, top, left_width)
    data = StringIO.new(image.download)
    @pdf.bounding_box([left_width + 12, top], width: @pdf.bounds.width - left_width - 12) do
      @pdf.image(data, fit: [@pdf.bounds.width, 165], position: :center)
      @pdf.move_down 4
      @pdf.text('*Imagem ilustrativa', size: 7, align: :right)
    end
    @pdf.cursor
  rescue StandardError
    top
  end

  def features(list)
    list = Array(list).compact_blank
    return if list.empty?

    @pdf.text('EQUIPAMENTO', style: :bold, size: 11)
    @pdf.move_down 6
    @pdf.text(clean("• #{list.join('  •  ')}"), leading: 3)
  end

  # ---------- papel timbrado e números de página ----------

  # Cabeçalho e rodapé entram uma vez no arquivo e se repetem em todas as páginas
  def letterhead(header, footer)
    pdf = @pdf
    footer_top = @footer_height + 14
    pdf.repeat(:all) do
      pdf.canvas do
        pdf.image(StringIO.new(header), at: [0, pdf.bounds.top], width: pdf.bounds.width) if header
        pdf.image(StringIO.new(footer), at: [0, footer_top], width: pdf.bounds.width) if footer
      end
    end
    pdf.number_pages('<page> / <total>', at: [pdf.bounds.right - 60, -(@footer_height + 22) + 12], width: 60, align: :right, size: 7)
  end

  def letterhead_height(data)
    return 30 if data.nil?

    info = Prawn::Images.const_get(data.byteslice(0, 2) == "\xFF\xD8".b ? :JPG : :PNG).new(data)
    PDF::Core::PageGeometry::SIZES['A4'][0] * info.height / info.width.to_f
  rescue StandardError
    30
  end

  def image_data(attachment, default_path)
    return attachment.download if attachment.attached?
    return File.binread(default_path) if @template.content['default_letterhead'] && File.exist?(default_path)

    nil
  end
end
