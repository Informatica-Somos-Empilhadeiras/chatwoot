# OUTSIDER: bloco das máquinas do PDF da proposta: para cada item com "características no PDF", a tabela
# de características com a imagem do catálogo (à direita ou à esquerda) e a lista do equipamento. Parte do
# Outsider::Crm::ProposalPdf.
module Outsider::Crm::ProposalPdf::Machines
  IMAGE_HEIGHT = 165
  GAP = 12

  private

  def machines_block(block)
    detailed = @proposal.items.select { |item| item.show_details && item.details.present? }
    detailed.each_with_index do |item, index|
      @pdf.move_down 10 if index.positive?
      say(item.description, bold: true) if detailed.size > 1
      specs_with_image(item, block)
      features(item.details['features'], block) if block['equipment']
    end
  end

  def specs_with_image(item, block)
    specs = Array(item.details['specs'])
    image = item.image
    return if specs.empty? && image.nil?

    machine_heading(block)
    top = @pdf.cursor
    table_width = image ? @pdf.bounds.width * 0.6 : @pdf.bounds.width
    left_image = image && block['image_side'] == 'left'
    bottoms = [specs_box(specs, top, table_width, left_image)]
    bottoms << product_image(image, top, *image_box(table_width, left_image)) if image
    @pdf.move_cursor_to(bottoms.min)
    @pdf.move_down 14
  end

  def specs_box(specs, top, table_width, left_image)
    left = left_image ? @pdf.bounds.width - table_width : 0
    @pdf.bounding_box([left, top], width: table_width) { specs_table(specs) } if specs.any?
    @pdf.cursor
  end

  def machine_heading(block)
    say(@fields.apply(block['heading']), bold: true, size: block['size'] + 1) if block['heading'].present?
    @pdf.move_down 16
  end

  # esquerda e largura da imagem, do lado que sobra do quadro
  def image_box(table_width, left_image)
    [left_image ? 0 : table_width + GAP, @pdf.bounds.width - table_width - GAP]
  end

  def specs_table(specs)
    rows = specs.map do |spec|
      style = spec['bold'] || @style&.dig(:bold) ? :bold : :normal
      [{ content: clean(spec['label']), font_style: style }, { content: clean(spec['value']), font_style: style }]
    end
    @pdf.table(rows, width: @pdf.bounds.width, column_widths: { 1 => @pdf.bounds.width * 0.3 },
                     cell_style: { borders: [], padding: [0.5, 2], size: block_size })
  end

  def product_image(image, top, left, width)
    data = StringIO.new(image.download)
    @pdf.bounding_box([left, top], width: width) do
      @pdf.image(data, fit: [@pdf.bounds.width, IMAGE_HEIGHT], position: :center)
      @pdf.move_down 4
      @pdf.text('*Imagem ilustrativa', size: 7, align: :right)
    end
    @pdf.cursor
  rescue StandardError
    top
  end

  def features(list, block)
    list = Array(list).compact_blank
    return if list.empty?

    say(@fields.apply(block['equipment_heading']), bold: true, size: block['size'] + 2) if block['equipment_heading'].present?
    @pdf.move_down 6
    say("• #{list.join('  •  ')}", leading: 3)
  end
end
