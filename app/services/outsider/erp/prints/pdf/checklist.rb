# OUTSIDER: bloco "Checklist" do Outsider::Erp::Prints::Pdf.
# - Com fotos: cada item do checklist vira um grupo, com o título (faixa, ao lado, cartão ou compacto), a quantidade de
#   fotos, a resposta de chegada/saída e as fotos (arranjo automático: 1 grande, 2 lado a lado, 3 em linha, 4+ em grade).
# - Sem fotos: só as respostas, em tabela, lista ou grade.
# O filtro de seções deixa espalhar o checklist pelo relatório (cada bloco com as seções dele).
# rubocop:disable Metrics -- desenho do PDF: coordenadas e medidas ficam juntas para dar para acompanhar o layout
module Outsider::Erp::Prints::Pdf::Checklist
  # altura máxima da foto por tamanho: [em grade, sozinha na linha]
  PHOTO_HEIGHTS = { 's' => [80, 120], 'm' => [125, 200], 'l' => [185, 290] }.freeze
  PHOTO_GAP = 6
  SIDE_WIDTH = 130
  THUMB = 44
  KEEP_WITH_PHOTOS = 150

  private

  def block_checklist(block)
    sections = checklist_sections(block)
    return if sections.empty?

    # o título não fica sozinho no pé da página: cabe junto com o começo do primeiro grupo
    need((base * 4) + (block['photos'] == 'without' ? base * 5 : KEEP_WITH_PHOTOS)) if block['title'].present?
    section_title(block['title'])
    block['photos'] == 'without' ? checklist_answers(block, sections) : photo_groups(block, sections)
  end

  def checklist_sections(block)
    filters = Array(block['sections']).map { |name| plain(name) }
    list = Array(@values['checklist'])
    filters.any? ? list.select { |section| filters.include?(plain(section['nome'])) } : list
  end

  def plain(text) = I18n.transliterate(text.to_s).squish.downcase

  def checklist_section_name(name, keep: base * 3)
    return if name.blank?

    need((base * 3) + keep)
    @pdf.move_down(2)
    @pdf.font(heading_font, style: :bold) do
      @pdf.text(clean(name).upcase, size: base - 0.5, color: color('muted'), character_spacing: 0.5)
    end
    @pdf.move_down(4)
  end

  def reading(item)
    arrival = item['chegada'].to_s
    departure = item['saida'].to_s
    return arrival if departure.blank? || departure == arrival
    return departure if arrival.blank?

    "Chegada: #{arrival}  ·  Saída: #{departure}"
  end

  # ---- com fotos ----

  def photo_groups(block, sections)
    sections.each do |section|
      items = Array(section['itens']).select { |item| item_photos(item).any? || block['show_empty'] }
      next if items.empty?

      checklist_section_name(section['nome'], keep: item_photos(items.first).any? ? KEEP_WITH_PHOTOS : base * 3) if block['show_sections']
      items.each_with_index do |item, index|
        @pdf.move_down(PHOTO_GAP + 2) if index.positive?
        photo_group(block, item)
      end
      @pdf.move_down(4)
    end
  end

  def item_photos(item)
    @item_photos ||= {}.compare_by_identity
    @item_photos[item] ||= Array(item['fotos']).filter_map { |photo| photo_bytes(photo) }
  end

  def photo_bytes(photo)
    bytes = photo.is_a?(Hash) ? sample_photo(photo['sample']) : photo
    image?(bytes) ? bytes : nil
  end

  def sample_photo(name)
    @samples ||= {}
    @samples[name] ||= begin
      path = Outsider::Erp::Prints::Sample.photo_path(name)
      path && File.exist?(path) ? File.binread(path) : ''
    end
  end

  def photo_group(block, item)
    photos = item_photos(item).first(block['max'].to_i.clamp(1, 30))
    case block['title_style']
    when 'side' then side_group(block, item, photos)
    when 'compact' then compact_group(block, item, photos)
    when 'card' then card_group(block, item, photos)
    else band_group(block, item, photos)
    end
  end

  def columns_for(block, count)
    case block['arrangement']
    when 'grid2' then 2
    when 'grid3' then 3
    when 'one' then 1
    else if count >= 5
           3
         else
           [count, 1].max.clamp(1, 3).then { |cols| count == 4 ? 2 : cols }
         end
    end
  end

  def photo_height(block, columns, width)
    heights = PHOTO_HEIGHTS.fetch(block['size'], PHOTO_HEIGHTS['m'])
    [width * 0.75, columns == 1 ? heights[1] : heights[0]].min
  end

  def count_label(block, photos)
    return '' unless block['show_count'] && photos.any?

    photos.size == 1 ? '1 foto' : "#{photos.size} fotos"
  end

  # faixa na cor principal com o nome do item e a quantidade; a resposta embaixo; as fotos em grade
  def band_group(block, item, photos)
    columns = columns_for(block, photos.size)
    cell = (width_of_page - (PHOTO_GAP * (columns - 1))) / columns
    height = photo_height(block, columns, cell)
    need(base + 12 + (photos.any? ? height + 8 : 0) + 14)
    band(item['atributo'], count_label(block, photos))
    reading_line(block, item)
    photo_rows(block, photos, 0, width_of_page, columns, height)
  end

  def band(title, count)
    top = @pdf.cursor
    band_height = base + 9
    @pdf.fill_color(color('primary'))
    @pdf.fill_rounded_rectangle([0, top], width_of_page, band_height, 3)
    @pdf.font(heading_font, style: :bold) do
      box(clean(title), contrast('primary'), at: [7, top - 4.5], width: width_of_page - 80, height: base + 2, size: base,
                                             overflow: :shrink_to_fit)
    end
    box(clean(count), contrast('primary'), at: [width_of_page - 76, top - 5], width: 70, align: :right, size: base - 1.5, height: base + 2)
    @pdf.fill_color(color('text'))
    @pdf.move_cursor_to(top - band_height - 4)
  end

  def reading_line(block, item, left: 0, width: width_of_page)
    text = block['show_reading'] ? reading(item) : ''
    return if text.blank?

    @pdf.bounding_box([left, @pdf.cursor], width: width) do
      @pdf.text(clean(text), size: base - 1, color: color('muted'), style: :italic)
    end
    @pdf.move_down(4)
  end

  # fotos em linhas de `columns`; cada linha que não couber vai para a página seguinte
  def photo_rows(block, photos, left, width, columns, height)
    return if photos.empty?

    cell = (width - (PHOTO_GAP * (columns - 1))) / columns
    photos.each_slice(columns).with_index do |row, row_index|
      need(height + PHOTO_GAP)
      top = @pdf.cursor
      row.each_with_index do |bytes, index|
        number = (row_index * columns) + index + 1
        draw_photo(bytes, left + (index * (cell + PHOTO_GAP)), top, cell, height, block['numbering'] ? "#{number}/#{photos.size}" : nil)
      end
      @pdf.move_cursor_to(top - height - PHOTO_GAP)
    end
  end

  # foto centrada numa célula com fundo claro e, se pedido, o número no canto
  def draw_photo(bytes, left, top, width, height, number)
    @pdf.fill_color(color('row'))
    @pdf.fill_rounded_rectangle([left, top], width, height, 3)
    ratio_w, ratio_h = image_size(bytes)
    scale = [width / ratio_w, height / ratio_h].min
    shown_w = ratio_w * scale
    shown_h = ratio_h * scale
    @pdf.image(StringIO.new(bytes), at: [left + ((width - shown_w) / 2), top - ((height - shown_h) / 2)], width: shown_w, height: shown_h)
    photo_number(number, left + width, top - height) if number
    @pdf.fill_color(color('text'))
  rescue Prawn::Errors::UnsupportedImageType, StandardError => e
    Rails.logger.warn("[Prints::Pdf] foto não desenhada: #{e.message}")
  end

  def photo_number(text, right, bottom)
    size = base - 2.5
    width = @pdf.width_of(text, size: size) + 8
    @pdf.transparent(0.6) do
      @pdf.fill_color('000000')
      @pdf.fill_rounded_rectangle([right - width - 3, bottom + size + 7], width, size + 4, 2)
    end
    box(text, 'FFFFFF', at: [right - width - 3, bottom + size + 5], width: width, align: :center, size: size)
  end

  # título numa coluna à esquerda (com o traço de destaque) e as fotos à direita
  def side_group(block, item, photos)
    columns = [columns_for(block, photos.size), 3].min
    width = width_of_page - SIDE_WIDTH - 10
    cell = (width - (PHOTO_GAP * (columns - 1))) / columns
    height = photos.any? ? photo_height(block, columns, cell) : 0
    need([height, 40].max + 6)
    top = @pdf.cursor
    @pdf.fill_color(color('accent'))
    @pdf.fill_rectangle([0, top], 3, [height, 36].max)
    @pdf.fill_color(color('text'))
    @pdf.bounding_box([10, top], width: SIDE_WIDTH - 12) do
      @pdf.font(heading_font, style: :bold) { @pdf.text(clean(item['atributo']), size: base, color: color('primary')) }
      count = count_label(block, photos)
      @pdf.text(clean(count), size: base - 1.5, color: color('muted')) if count.present?
      @pdf.move_down(2)
      @pdf.text(clean(reading(item)), size: base - 1, color: color('muted'), style: :italic) if block['show_reading'] && reading(item).present?
    end
    text_bottom = @pdf.cursor
    @pdf.move_cursor_to(top)
    photo_rows(block, photos, SIDE_WIDTH + 10, width, columns, height)
    @pdf.move_cursor_to([@pdf.cursor, text_bottom - 4].min)
  end

  # as fotos dentro de um cartão com borda e o nome do item no rodapé
  def card_group(block, item, photos)
    columns = columns_for(block, photos.size)
    inner = width_of_page - 12
    cell = (inner - (PHOTO_GAP * (columns - 1))) / columns
    height = photos.any? ? photo_height(block, columns, cell) : 0
    rows = photos.each_slice(columns).count
    total = 6 + (rows * (height + PHOTO_GAP)) + base + 16
    return band_group(block, item, photos) if total > @pdf.bounds.height - 20

    need(total)
    top = @pdf.cursor
    @pdf.move_down(6)
    photo_rows(block, photos, 6, inner, columns, height)
    footer_top = @pdf.cursor
    @pdf.stroke_color(color('line'))
    @pdf.line_width(0.6)
    @pdf.stroke_line([0, footer_top], [width_of_page, footer_top]) if photos.any?
    @pdf.bounding_box([8, footer_top - 5], width: width_of_page - 16) do
      title = "<b>#{esc(item['atributo'])}</b>"
      count = count_label(block, photos)
      title += " <color rgb='#{color('muted')}'>· #{esc(count)}</color>" if count.present?
      text = block['show_reading'] ? reading(item) : ''
      title += "  <color rgb='#{color('muted')}'><i>#{esc(text)}</i></color>" if text.present?
      @pdf.text(title, size: base, inline_format: true)
    end
    bottom = @pdf.cursor - 5
    @pdf.stroke_rounded_rectangle([0, top], width_of_page, top - bottom, 4)
    @pdf.move_cursor_to(bottom)
  end

  # uma linha: nome e resposta à esquerda, miniaturas à direita (bom para muitos itens)
  def compact_group(block, item, photos)
    left_width = width_of_page * 0.42
    thumbs_width = width_of_page - left_width - 8
    per_row = [((thumbs_width + 4) / ((THUMB * 1.33) + 4)).floor, 1].max
    rows = photos.each_slice(per_row).to_a
    height = [rows.size * (THUMB + 4), base + 8].max
    need(height + 6)
    top = @pdf.cursor
    @pdf.bounding_box([0, top], width: left_width) do
      title = "<b>#{esc(item['atributo'])}</b>"
      count = count_label(block, photos)
      title += " <color rgb='#{color('muted')}'>(#{esc(count)})</color>" if count.present?
      @pdf.text(title, size: base, inline_format: true)
      @pdf.text(clean(reading(item)), size: base - 1, color: color('muted'), style: :italic) if block['show_reading'] && reading(item).present?
    end
    text_bottom = @pdf.cursor
    rows.each_with_index do |row, row_index|
      row.each_with_index do |bytes, index|
        draw_photo(bytes, left_width + 8 + (index * ((THUMB * 1.33) + 4)), top - (row_index * (THUMB + 4)), THUMB * 1.33, THUMB, nil)
      end
    end
    @pdf.move_cursor_to([text_bottom, top - height].min - 2)
    @pdf.stroke_color(color('line'))
    @pdf.line_width(0.4)
    @pdf.stroke_horizontal_rule
    @pdf.move_down(3)
  end

  # ---- sem fotos: só as respostas ----

  def checklist_answers(block, sections)
    case block['answers']
    when 'list' then answers_list(block, sections)
    when 'grid' then answers_grid(block, sections)
    else answers_table(block, sections)
    end
  end

  def answered(block, items)
    Array(items).select { |item| block['show_empty'] || item['chegada'].present? || item['saida'].present? }
  end

  def answers_table(block, sections)
    columns = chosen('checklist')
    columns = columns.reject { |column| column.first == 'secao' } unless block['show_sections']
    rows = sections.flat_map do |section|
      answered(block, section['itens']).map do |item|
        { 'secao' => section['nome'], 'item' => item['atributo'], 'chegada' => item['chegada'], 'saida' => item['saida'] }
      end
    end
    return if rows.empty? || columns.empty?

    data_table('checklist', columns, rows)
  end

  def answers_list(block, sections)
    sections.each do |section|
      items = answered(block, section['itens'])
      next if items.empty?

      checklist_section_name(section['nome']) if block['show_sections']
      items.each do |item|
        @pdf.text("<b>#{esc(item['atributo'])}:</b> #{esc(reading(item).presence || '-')}", size: base, inline_format: true, leading: 1)
        @pdf.move_down(2)
      end
      @pdf.move_down(4)
    end
  end

  def answers_grid(block, sections)
    columns = block['grid_columns'].to_i.clamp(2, 3)
    sections.each do |section|
      items = answered(block, section['itens'])
      next if items.empty?

      checklist_section_name(section['nome']) if block['show_sections']
      cells = items.map { |item| field_cell([item['atributo'], reading(item)], 'boxes') }
      rows = cells.each_slice(columns).map { |slice| slice + Array.new(columns - slice.size, '') }
      @pdf.table(rows, width: width_of_page, column_widths: Array.new(columns, width_of_page / columns.to_f),
                       cell_style: { inline_format: true, size: base, padding: [4, 6, 5, 6], border_width: 0.6,
                                     border_color: color('line'), text_color: color('text') })
      @pdf.move_down(6)
    end
  end
end
# rubocop:enable Metrics
