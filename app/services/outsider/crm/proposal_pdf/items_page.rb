# OUTSIDER: itens, total e condições da proposta (quadro na venda, lista na locação) e, na locação, as
# partes. Parte do Outsider::Crm::ProposalPdf.
module Outsider::Crm::ProposalPdf::ItemsPage
  private

  def font_size
    Outsider::Crm::ProposalPdf::FONT_SIZE
  end

  def items_page
    @pdf.start_new_page
    proposal_number_line
    items_table
    @pdf.move_down 28
    @template.conditions_style == 'list' ? conditions_list : conditions_table
    parties if @template.flag?(:show_parties)
  end

  def proposal_number_line
    @pdf.text("<b>PROPOSTA</b>  <b>#{@proposal.number}</b>", inline_format: true, align: :right)
    @pdf.move_down 2
  end

  def items_table
    discount = @template.flag?(:show_discount)
    header = ['Item', 'Descrição', 'Qtd.', 'Valor Unit.', ('Desc.' if discount), 'Total'].compact
    rows = @proposal.items.each_with_index.map { |item, index| item_row(item, index, discount) }
    rows << [{ content: total_line, colspan: header.size, align: :right, inline_format: true, padding: [7, 4] }]
    @pdf.table([header] + rows, header: true, column_widths: item_widths(discount),
                                cell_style: { size: font_size, border_width: 1, padding: [3, 3], valign: :center }) do |table|
      table.row(0).font_style = :bold
      table.columns(2..(header.size - 1)).align = :right
      table.column(0).align = :center
    end
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

  def conditions_table
    rows = @proposal.conditions.map do |condition|
      [{ content: markup(condition['label']), inline_format: true }, { content: markup(condition['text']), inline_format: true }]
    end
    return if rows.empty?

    @pdf.table(rows, width: @pdf.bounds.width, column_widths: { 0 => 128 },
                     cell_style: { size: font_size, border_width: 1, padding: [3, 4], valign: :center })
    closing_text
  end

  def conditions_list
    return if @proposal.conditions.empty?

    heading = @template.text(:conditions_heading)
    if heading.present?
      @pdf.text(clean(heading), style: :bold)
      @pdf.move_down 10
    end
    @proposal.conditions.each do |condition|
      label = condition['label'].present? ? "#{markup(condition['label'])}: " : ''
      @pdf.text("• #{label}#{markup(condition['text'])}", inline_format: true, align: :justify)
    end
  end

  def parties
    @pdf.move_down 24
    @pdf.text('PARTES:', style: :bold)
    @pdf.move_down 10
    [@template.text(:parties_text), @template.text(:acceptance_text)].compact_blank.each do |text|
      rich(text, align: :justify)
      @pdf.move_down 8
    end
    closing_text
  end

  def closing_text
    text = @template.text(:closing)
    return if text.blank?

    @pdf.move_down 8
    rich(text, align: :justify)
  end
end
