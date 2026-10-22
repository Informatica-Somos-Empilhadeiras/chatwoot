# OUTSIDER: desenho do modelo de proposta (editor de modelos, Entrega 16), guardado no content do modelo:
#
# blocks: o conteúdo em sequência, na ordem do PDF. Cada bloco pode ser escondido, começar numa página nova
#         e ter tamanho de letra, negrito e destaque amarelo próprios. Os textos dos blocos padrão continuam
#         nas chaves de sempre do content (intro, closing...); o bloco "text" é um texto livre com título.
# layout: fonte, margens (em mm), em quais páginas entram o cabeçalho e o rodapé e os elementos em posição
#         livre no papel timbrado (texto ou imagem, em mm a partir do canto de cima à esquerda da folha A4),
#         em todas as páginas ou só na primeira.
#
# O conteúdo fica em blocos e não em posição livre porque o tamanho muda de uma proposta para outra (mais
# itens, mais condições): solto, um texto maior passaria por cima do outro. Modelo antigo, sem blocks,
# ganha a sequência das Entregas 14 e 15 (mesmo PDF).
module Outsider::Crm::ProposalTemplateLayout
  module_function

  BLOCK_TYPES = %w[date_number customer intro title specs items conditions parties closing bank signature notes text].freeze
  FONTS = %w[Helvetica Times-Roman Courier].freeze
  PAGES = %w[all first].freeze
  ALIGNS = %w[left center right].freeze
  ELEMENT_TYPES = %w[text image].freeze
  MAX_BLOCKS = 40
  MAX_ELEMENTS = 20
  MAX_TEXT = 5_000
  PAGE_WIDTH_MM = 210
  PAGE_HEIGHT_MM = 297
  DEFAULT_MARGINS = { 'side' => 12.7, 'top' => 6.4, 'bottom' => 7.8 }.freeze
  # tamanho de letra padrão de cada bloco (o resto do PDF usa 9)
  DEFAULT_SIZES = { 'title' => 10, 'signature' => 10 }.freeze
  DEFAULT_HEADINGS = { 'specs' => 'Principais Características' }.freeze
  EQUIPMENT_HEADING = 'EQUIPAMENTO'.freeze

  def default_blocks(content)
    [
      block('date_number'), block('customer'), block('intro'), block('title'),
      block('specs', visible: content['show_specs'] == true),
      block('items', new_page: true), block('conditions'), block('parties', visible: content['show_parties'] == true),
      block('closing'), block('bank', new_page: true, visible: content['show_bank'] == true), block('signature'), block('notes')
    ]
  end

  # specs (características das máquinas) também mostra o equipamento de cada máquina, com o título próprio
  def block(type, visible: true, new_page: false)
    data = { 'key' => type, 'type' => type, 'visible' => visible, 'new_page' => new_page, 'size' => DEFAULT_SIZES.fetch(type, 9),
             'bold' => false, 'highlight' => false, 'heading' => DEFAULT_HEADINGS.fetch(type, ''), 'text' => '' }
    type == 'specs' ? data.merge('image_side' => 'right', 'equipment' => true, 'equipment_heading' => EQUIPMENT_HEADING) : data
  end

  def default_layout
    { 'font' => FONTS.first, 'margins' => DEFAULT_MARGINS.dup, 'header_pages' => 'all', 'footer_pages' => 'all', 'elements' => [] }
  end

  def blocks(content)
    content['blocks'].is_a?(Array) ? content['blocks'] : default_blocks(content)
  end

  def layout(content)
    default_layout.merge(content['layout'].is_a?(Hash) ? content['layout'] : {})
  end

  # Limpa o que veio do navegador: tipos conhecidos, cada bloco padrão uma vez só, números dentro dos limites
  def normalize_blocks(list)
    seen = []
    Array(list).first(MAX_BLOCKS).each_with_index.filter_map do |raw, index|
      raw = raw.to_h.stringify_keys
      type = raw['type'].to_s
      next unless BLOCK_TYPES.include?(type) && (type == 'text' || seen.exclude?(type))

      seen << type
      normalize_block(raw, type, index)
    end
  end

  def normalize_block(raw, type, index)
    base = block(type)
    data = base.merge(block_style(raw, base)).merge(
      'key' => type == 'text' ? raw['key'].to_s.presence&.first(40) || "text-#{index}" : type,
      'heading' => heading(raw, 'heading', base['heading']), 'text' => raw['text'].to_s.first(MAX_TEXT)
    )
    type == 'specs' ? data.merge(machine_options(raw)) : data
  end

  def block_style(raw, base)
    { 'visible' => boolean(raw.fetch('visible', true)), 'new_page' => boolean(raw['new_page']),
      'size' => number(raw['size'], base['size'], 6..16), 'bold' => boolean(raw['bold']), 'highlight' => boolean(raw['highlight']) }
  end

  def machine_options(raw)
    { 'image_side' => pick(raw['image_side'], %w[right left]), 'equipment' => boolean(raw.fetch('equipment', true)),
      'equipment_heading' => heading(raw, 'equipment_heading', EQUIPMENT_HEADING) }
  end

  def heading(raw, key, default)
    raw.key?(key) ? raw[key].to_s.strip.first(200) : default
  end

  def normalize_layout(raw)
    raw = raw.to_h.stringify_keys
    margins = raw['margins'].to_h.stringify_keys
    { 'font' => pick(raw['font'], FONTS), 'margins' => DEFAULT_MARGINS.to_h { |key, default| [key, number(margins[key], default, 0..80)] },
      'header_pages' => pick(raw['header_pages'], PAGES), 'footer_pages' => pick(raw['footer_pages'], PAGES),
      'elements' => Array(raw['elements']).first(MAX_ELEMENTS).filter_map { |element| normalize_element(element.to_h.stringify_keys) } }
  end

  def normalize_element(raw)
    return unless ELEMENT_TYPES.include?(raw['type'])

    {
      'id' => raw['id'].to_s.presence&.first(40) || SecureRandom.hex(4), 'type' => raw['type'],
      'x' => number(raw['x'], 20, 0..PAGE_WIDTH_MM), 'y' => number(raw['y'], 20, 0..PAGE_HEIGHT_MM),
      'width' => number(raw['width'], 60, 5..PAGE_WIDTH_MM), 'pages' => pick(raw['pages'], PAGES),
      'image_id' => raw['image_id'].presence&.to_i
    }.merge(element_text(raw))
  end

  def element_text(raw)
    color = raw['color'].to_s.delete('#')
    { 'text' => raw['text'].to_s.first(1_000), 'size' => number(raw['size'], 9, 6..40), 'bold' => boolean(raw['bold']),
      'highlight' => boolean(raw['highlight']), 'color' => color.match?(/\A\h{6}\z/) ? color : '000000',
      'align' => pick(raw['align'], ALIGNS) }
  end

  # valor da lista ou o primeiro dela
  def pick(value, list)
    list.include?(value) ? value : list.first
  end

  def boolean(value)
    ActiveModel::Type::Boolean.new.cast(value) || false
  end

  def number(value, default, range)
    number = Float(value, exception: false)
    return default if number.nil?

    number.clamp(range.begin, range.end).round(1)
  end
end
