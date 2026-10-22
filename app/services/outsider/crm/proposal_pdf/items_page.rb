# OUTSIDER: blocos de itens e total, condições (quadro ou lista), partes e fechamento do PDF da proposta.
# Parte do Outsider::Crm::ProposalPdf.
module Outsider::Crm::ProposalPdf::ItemsPage
  private

  def items_block(_block)
    discount = @template.flag?(:show_discount)
    header = ['Item', 'Descrição', 'Qtd.', 'Valor Unit.', ('Desc.' if discount), 'Total'].compact
    rows = @proposal.items.each_with_index.map { |item, index| item_row(item, index, discount) }
    rows << [{ content: total_line, colspan: header.size, align: :right, inline_format: true, padding: [7, 4] }]
    @pdf.table([header] + rows, header: true, column_widths: item_widths(discount), cell_style: table_style(3)) do |table|
      table.row(0).font_style = :bold
      table.columns(2..(header.size - 1)).align = :right
      table.column(0).align = :center
    end
  end

  # tamanho e negrito do bloco valem também nos quadros; destaque pinta o fundo das células
  def table_style(padding)
    style = { size: block_size, border_width: 1, padding: [3, padding], valign: :center }
    style[:font_style] = :bold if @style&.dig(:bold)
    style[:background_color] = Outsider::Crm::ProposalPdf::HIGHLIGHT if @style&.dig(:highlight)
    style
  end

  def item_row(item, index, discount)
    [(index + 1).to_s, clean(item.description), quantity(item.quantity), money(item.unit_price_cents),
     (money(item.discount_cents) if discount), money(item.total_cents)].compact
  end

  def total_line
    "<b>#{escape(@template.text(:total_label).presence || 'Total:')}</b> #{money(@proposal.total_cents)}"
  end

  # Descrição fica com o que sobra da largura da página
  def item_widths(discount)
    widths = discount ? [26, 0, 50, 75, 75, 82] : [26, 0, 55, 85, 90]
    widths[1] = @pdf.bounds.width - widths.sum
    widths
  end

  def conditions_block(_block)
    @template.conditions_style == 'list' ? conditions_list : conditions_table
  end

  def conditions_table
    rows = @proposal.conditions.map do |condition|
      [{ content: markup(condition['label'], table: true), inline_format: true },
       { content: markup(condition['text'], table: true), inline_format: true }]
    end
    return if rows.empty?

    @pdf.table(rows, width: @pdf.bounds.width, column_widths: { 0 => 128 }, cell_style: table_style(4))
  end

  def conditions_list
    return if @proposal.conditions.empty?

    heading = @template.text(:conditions_heading)
    if heading.present?
      say(@fields.apply(heading), bold: true)
      @pdf.move_down 10
    end
    @proposal.conditions.each do |condition|
      label = condition['label'].present? ? "#{markup(condition['label'])}: " : ''
      write(fragments("• #{label}#{markup(condition['text'])}"), align: :justify)
    end
  end

  def parties_block(_block)
    say('PARTES:', bold: true)
    @pdf.move_down 10
    [@template.text(:parties_text), @template.text(:acceptance_text)].compact_blank.each do |text|
      rich(text, align: :justify)
      @pdf.move_down 8
    end
  end

  def closing_block(_block)
    text = @template.text(:closing)
    rich(text, align: :justify) if text.present?
  end
end
