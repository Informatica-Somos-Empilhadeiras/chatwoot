# OUTSIDER: o checklist do relatório da OS, como no original: nome da seção no centro, cada item com o nome à esquerda e
# a leitura (CHEGADA/SAÍDA) a partir do meio, em negrito, e as fotos embaixo em 4 colunas de largura fixa e altura
# natural (a linha tem a altura da mais alta e as outras ficam no meio). Parte do Outsider::Erp::ServiceOrderPdf.
module Outsider::Erp::ServiceOrderPdf::Checklist
  include Outsider::Erp::ServiceOrderPdf::Layout

  private

  def checklist
    @report['checklist'].each do |section|
      baseline = @y + SECTION_GAP.fetch(@after, 24.0)
      baseline = page_break(24.72) if baseline + 21.84 + first_block(section['itens'].first) > BOTTOM
      write_center(section['nome'], baseline)
      @y = baseline
      @after = :section
      section['itens'].each { |item| checklist_item(item) }
    end
  end

  def checklist_item(item)
    baseline = @y + (@after == :photos ? 33.84 : 21.84)
    baseline = page_break(24.72) if baseline + first_block(item) > BOTTOM
    @y = item_header(item, baseline)
    @after = :item
    photo_rows(item['fotos']).each { |row| photo_row(row) }
  end

  # devolve a linha de base da última linha (o nome do item quebra dentro da metade esquerda)
  def item_header(item, baseline)
    names = wrap(item['atributo'], ITEM_WIDTH, style: :bold)
    readings = wrap(reading(item), ITEM_WIDTH, style: :bold)
    names.each_with_index { |line, row| write(line, [ITEM_X, baseline + (LINE * row)], style: :bold) }
    readings.each_with_index { |line, row| write(line, [READING_X, baseline + (LINE * row)], style: :bold) }
    baseline + (LINE * ([names.size, readings.size].max - 1))
  end

  def reading(item) = [label('CHEGADA', item['chegada']), label('SAÍDA', item['saida'])].compact.join('    ')

  # do nome do item até o fim da 1ª linha de fotos, para o nome não ficar sozinho no pé da página
  def first_block(item)
    return LINE unless item

    rows = photo_rows(item['fotos'])
    LINE + (rows.any? ? PHOTO_GAP + rows.first[:height] : 0)
  end

  # 4 por linha, cada foto com a largura da coluna e a altura natural; a linha tem a altura da mais alta
  def photo_rows(photos)
    sized = photos.filter_map do |bytes|
      _, info = @pdf.build_image_object(StringIO.new(bytes))
      [bytes, PHOTO_WIDTH * info.height / info.width]
    rescue Prawn::Errors::UnsupportedImageType, StandardError
      nil
    end
    sized.each_slice(4).map { |row| { photos: row, height: row.map(&:last).max } }
  end

  def photo_row(row)
    top = @y + PHOTO_GAP
    top = page_break(12.0) if top + row[:height] > BOTTOM
    row[:photos].each_with_index do |(bytes, height), index|
      @pdf.image(StringIO.new(bytes), at: [PHOTO_X[index], PAGE_HEIGHT - (top + ((row[:height] - height) / 2))], width: PHOTO_WIDTH)
    end
    @y = top + row[:height]
    @after = :photos
  end
end
