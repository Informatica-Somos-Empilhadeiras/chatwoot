# OUTSIDER: PDF do relatório de uma OS no modelo da "Impressão de Ordem de Serviço - Check-List" do kanban de KPI do Mais
# Prático: cabeçalho com logo e dados do emitente (o mesmo do orçamento), cliente e equipamento, serviço, check-in/out,
# avaliação técnica, produtos e o checklist com as fotos em grade. Só desenha o hash do Outsider::Erp::ServiceOrderReport.
# Fontes do próprio PDF: o texto sai em Windows-1252.
class Outsider::Erp::ServiceOrderPdf
  include Outsider::Erp::QuotePdfText
  MARGIN = 28
  FONT_SIZE = 9
  LABEL_COLOR = '1F4E79'.freeze
  TITLE_COLOR = '7A808A'.freeze
  PHOTOS_PER_ROW = 4
  PHOTO_HEIGHT = 150
  GAP = 8

  Prawn::Fonts::AFM.hide_m17n_warning = true

  def initialize(report)
    @report = report
  end

  def filename
    customer = @report.dig('cliente', 'nome').to_s.parameterize(separator: ' ').upcase.first(50)
    "OS #{@report['numero']} - #{customer}.pdf".squeeze(' ')
  end

  def render
    @pdf = Prawn::Document.new(page_size: 'A4', margin: MARGIN, info: { Title: clean(filename.delete_suffix('.pdf')), Creator: 'Chat' })
    @pdf.font('Helvetica', size: FONT_SIZE)
    header
    customer_and_equipment
    service
    events
    evaluation
    products
    checklist
    page_numbers
    @pdf.render
  end

  private

  def width = @pdf.bounds.width

  def header
    emitter = @report['emitente'].to_h
    @pdf.bounding_box([0, @pdf.cursor], width: width, height: 92) do
      @pdf.stroke_bounds
      logo(emitter['logo'])
      @pdf.bounding_box([96, 86], width: width - 270, height: 82) { emitter_lines(emitter) }
      heading(width - 170)
    end
  end

  # à direita do cabeçalho: número da OS e data de emissão
  def heading(left)
    @pdf.text_box(clean("Ordem de Serviço Nº #{@report['numero']}"), at: [left, 84], width: 162, align: :right, size: 12, style: :bold)
    @pdf.text_box('Check-List', at: [left, 66], width: 162, align: :right, size: 10)
    @pdf.text_box(clean("Emitido em #{Time.zone.today.strftime('%d/%m/%Y')}"), at: [left, 18], width: 162, align: :right, size: 9, style: :bold)
  end

  def customer_and_equipment
    customer = @report['cliente'].to_h
    equipment = @report['equipamento'].to_h
    title('Dados do cliente e equipamento')
    columns([['Cliente', customer['nome']], ['CNPJ/CPF', document(customer['documento'])], ['Endereço', customer['endereco']],
             ['Cidade', customer['cidade']]],
            [['Descrição', equipment['descricao']], ['Marca', equipment['marca']], ['Modelo', equipment['modelo']],
             ['Nº de série', equipment['serie']], ['Horímetro', equipment['horimetro']]])
  end

  def service
    data = @report['servico'].to_h
    title('Dados do serviço')
    columns([['Tipo de atendimento', data['tipo_atendimento']], ['Classificação', data['classificacao']]],
            [['Técnico principal', data['tecnico']]])
    field('Defeitos mencionados', data['defeitos'])
  end

  def events
    rows = @report['eventos'].map { |event| [event['tipo'], event['observacoes'], event['check_in'], event['check_out']] }
    return if rows.empty?

    title('Eventos (check-in/out)')
    table(%w[Evento Observações Check-in Check-out], rows, { 2 => 100, 3 => 100 })
  end

  def evaluation
    return if @report['avaliacao'].blank?

    title('Avaliação técnica')
    @pdf.text(clean(@report['avaliacao']), leading: 1.5)
  end

  def products
    rows = @report['produtos'].map { |item| [item['codigo'], item['descricao'], item['unidade'], qty(item['quantidade'])] }
    return if rows.empty?

    title('Produtos / serviços')
    table(%w[Código Descrição Unidade Qtd], rows, { 0 => 60, 2 => 55, 3 => 40 })
  end

  def checklist
    return if @report['checklist'].blank?

    title(@report['familia'].presence || 'Check-list', room_for(@report['checklist'].first) + 30)
    @report['checklist'].each do |section|
      @pdf.start_new_page if @pdf.cursor < room_for(section)
      @pdf.move_down 2
      @pdf.text(clean(section['nome']), size: 9.5, style: :bold, align: :center, color: TITLE_COLOR)
      section['itens'].each { |item| checklist_item(item) }
    end
  end

  # espaço para o nome da seção não ficar sozinho no pé da página, longe do primeiro item (e das fotos dele)
  def room_for(section) = section['itens'].first&.dig('fotos').present? ? PHOTO_HEIGHT + 50 : 60

  # nome do item à esquerda, leitura de chegada/saída à direita, fotos embaixo
  def checklist_item(item)
    @pdf.start_new_page if @pdf.cursor < (item['fotos'].any? ? PHOTO_HEIGHT + 30 : 30)
    @pdf.move_down 8
    top = @pdf.cursor
    @pdf.text_box(clean(reading(item)), at: [width - 190, top], width: 190, align: :right, size: 9, style: :bold)
    @pdf.bounding_box([0, top], width: width - 200) { @pdf.text(clean(item['atributo']), size: 9, style: :bold) }
    @pdf.move_down 4
    photos(item['fotos'])
  end

  def reading(item) = [label('CHEGADA', item['chegada']), label('SAÍDA', item['saida'])].compact.join('    ')

  def photos(list)
    cell = (width - (GAP * (PHOTOS_PER_ROW - 1))) / PHOTOS_PER_ROW
    list.each_slice(PHOTOS_PER_ROW) do |row|
      @pdf.start_new_page if @pdf.cursor < PHOTO_HEIGHT
      top = @pdf.cursor
      row.each_with_index { |bytes, index| photo(bytes, [index * (cell + GAP), top], cell) }
      @pdf.move_cursor_to(top - PHOTO_HEIGHT - GAP)
    end
  end

  def photo(bytes, at, cell)
    @pdf.bounding_box(at, width: cell, height: PHOTO_HEIGHT) do
      @pdf.image(StringIO.new(bytes), fit: [cell, PHOTO_HEIGHT], position: :center, vposition: :center)
    end
  rescue Prawn::Errors::UnsupportedImageType, StandardError
    nil
  end

  def title(text, room = 80)
    @pdf.start_new_page if @pdf.cursor < room
    @pdf.move_down 14
    @pdf.text(clean(text.upcase), size: 9, style: :bold, color: TITLE_COLOR, align: :center)
    @pdf.move_down 6
  end

  def field(name, value)
    @pdf.text(clean(name.upcase), size: 7.5, style: :bold, color: LABEL_COLOR)
    @pdf.text(clean(value.presence || '-'))
    @pdf.move_down 5
  end

  # duas colunas de campos lado a lado; o cursor segue da mais comprida
  def columns(left, right)
    top = @pdf.cursor
    half = (width - 16) / 2
    @pdf.bounding_box([0, top], width: half) { left.each { |name, value| field(name, value) } }
    left_bottom = @pdf.cursor
    @pdf.bounding_box([half + 16, top], width: half) { right.each { |name, value| field(name, value) } }
    @pdf.move_cursor_to([left_bottom, @pdf.cursor].min)
  end

  def table(head, rows, widths)
    cells = ([head] + rows).map { |row| row.map { |cell| clean(cell.to_s) } }
    style = { size: 8.5, padding: [3, 4], border_color: 'BFC5CD' }
    @pdf.table(cells, header: true, width: width, column_widths: widths, cell_style: style) do |table|
      table.row(0).font_style = :bold
      table.row(0).background_color = 'F1F3F5'
    end
  end

  def page_numbers
    return if @pdf.page_count < 2

    @pdf.number_pages('<page>/<total>', at: [width - 40, -6], width: 40, align: :right, size: 7)
  end
end
