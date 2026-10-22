# OUTSIDER: blocos livres do PDF da proposta (Entrega 17): imagem do modelo (largura em % da área do texto,
# à esquerda, no centro ou à direita), linha divisória e espaço em branco. Parte do Outsider::Crm::ProposalPdf.
module Outsider::Crm::ProposalPdf::FreeBlocks
  private

  def image_block(block)
    data = element_image(block['image_id'])
    return if data.nil?

    width = @pdf.bounds.width * block['width'] / 100.0
    @pdf.image(StringIO.new(data), fit: [width, @pdf.bounds.height], position: block['align'].to_sym)
  rescue Prawn::Errors::UnsupportedImageType
    nil
  end

  def divider_block(block)
    @pdf.move_down 2
    @pdf.stroke do
      @pdf.stroke_color(block['color'])
      @pdf.line_width(block['thickness'])
      @pdf.horizontal_rule
    end
    @pdf.stroke_color('000000')
    @pdf.line_width(1)
    @pdf.move_down 2 + block['thickness']
  end

  def spacer_block(block)
    space = mm(block['height'])
    space < @pdf.cursor - @pdf.bounds.bottom ? @pdf.move_down(space) : @pdf.bounds.move_past_bottom
  end
end
