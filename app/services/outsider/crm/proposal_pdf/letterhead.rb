# OUTSIDER: papel timbrado do PDF da proposta: cabeçalho e rodapé na largura da folha, elementos em posição
# livre (texto ou imagem) e o número da página. Cada um entra em todas as páginas ou só na primeira; as
# margens deixam o espaço do cabeçalho e do rodapé só nas páginas em que eles aparecem. Parte do
# Outsider::Crm::ProposalPdf.
module Outsider::Crm::ProposalPdf::Letterhead
  PAGE_HEIGHT = PDF::Core::PageGeometry::SIZES['A4'][1]
  PAGE_WIDTH = PDF::Core::PageGeometry::SIZES['A4'][0]

  private

  def prepare_letterhead
    @header = image_data(@template.header_image, Outsider::Crm::ProposalPdf::DEFAULT_HEADER)
    @footer = image_data(@template.footer_image, Outsider::Crm::ProposalPdf::DEFAULT_FOOTER)
    @header_height = letterhead_height(@header)
    @footer_height = letterhead_height(@footer)
  end

  def margins(page)
    margins = @layout['margins']
    header = page == :first || @layout['header_pages'] == 'all' ? @header_height : 0
    footer = page == :first || @layout['footer_pages'] == 'all' ? @footer_height : 0
    [header + mm(margins['top']), mm(margins['side']), footer + mm(margins['bottom']), mm(margins['side'])]
  end

  def first_page_margins
    margins(:first)
  end

  # Página nova (pelo bloco ou porque o texto não coube) usa as margens das páginas seguintes
  def keep_margins_on_new_pages
    top, side, bottom = margins(:next)
    @pdf.define_singleton_method(:start_new_page) do |options = {}|
      super({ top_margin: top, bottom_margin: bottom, left_margin: side, right_margin: side }.merge(options))
    end
  end

  def mm(value)
    value.to_f * Outsider::Crm::ProposalPdf::MM
  end

  def draw_letterhead
    stamp_image(@header, [0, PAGE_HEIGHT], PAGE_WIDTH, @layout['header_pages'])
    stamp_image(@footer, [0, @footer_height + 14], PAGE_WIDTH, @layout['footer_pages'])
    @layout['elements'].each { |element| draw_element(element) }
    page_numbers
  end

  # imagem em posição fixa da folha, em todas as páginas ou só na primeira
  def stamp_image(data, at, width, pages)
    return if data.nil?

    pdf = @pdf
    pdf.repeat(pages_for(pages)) { pdf.canvas { pdf.image(StringIO.new(data), at: at, width: width) } }
  end

  def pages_for(setting)
    setting == 'first' ? [1] : :all
  end

  def draw_element(element)
    at = [mm(element['x']), PAGE_HEIGHT - mm(element['y'])]
    width = mm(element['width'])
    return stamp_image(element_image(element['image_id']), at, width, element['pages']) if element['type'] == 'image'

    pdf = @pdf
    list = element_fragments(element)
    options = { at: at, width: width, size: element['size'], align: element['align'].to_sym, overflow: :expand }
    pdf.repeat(pages_for(element['pages'])) { pdf.canvas { pdf.formatted_text_box(list, options) } }
  end

  def element_fragments(element)
    fragments(markup(element['text'])).map do |fragment|
      styled(fragment, element['bold'], element['highlight']).merge(color: element['color'])
    end
  end

  def element_image(id)
    attachment = id && @template.layout_images.attachments.find { |item| item.id == id }
    attachment&.download
  rescue StandardError
    nil
  end

  # "1 / 3" no canto de baixo à direita, abaixo do rodapé
  def page_numbers
    total = @pdf.page_count
    side = mm(@layout['margins']['side'])
    (1..total).each do |page|
      @pdf.go_to_page(page)
      @pdf.canvas { @pdf.text_box("#{page} / #{total}", at: [PAGE_WIDTH - side - 60, 12], width: 60, align: :right, size: 7) }
    end
  end

  def letterhead_height(data)
    return 30 if data.nil?

    info = Prawn::Images.const_get(data.byteslice(0, 2) == "\xFF\xD8".b ? :JPG : :PNG).new(data)
    PAGE_WIDTH * info.height / info.width.to_f
  rescue StandardError
    30
  end

  def image_data(attachment, default_path)
    return attachment.download if attachment.attached?
    return File.binread(default_path) if @template.content['default_letterhead'] && File.exist?(default_path)

    nil
  end
end
