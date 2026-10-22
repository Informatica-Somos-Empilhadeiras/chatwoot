# OUTSIDER: última página da proposta: confirmação de pedido, dados bancários, para onde mandar a
# documentação, assinatura do vendedor e quadro de aceite do cliente. Parte do Outsider::Crm::ProposalPdf.
module Outsider::Crm::ProposalPdf::ClosingPage
  private

  def closing_page
    @pdf.start_new_page
    proposal_number_line
    @pdf.move_down 24
    company_blocks if @template.flag?(:show_bank)
    @pdf.move_down 30
    signatures
    notes
  end

  def company_blocks
    top = @pdf.cursor
    width = @pdf.bounds.width
    @pdf.bounding_box([0, top], width: width * 0.62) { order_and_bank }
    after_left = @pdf.cursor
    @pdf.bounding_box([width * 0.64, top], width: width * 0.36) do
      highlighted(@template.text(:documents_heading))
      bold_line(@company['trade_name'])
      plain_lines(@company['documents_email'])
    end
    @pdf.move_cursor_to([after_left, @pdf.cursor].min)
  end

  def order_and_bank
    highlighted(@template.text(:order_heading))
    bold_line(@company['legal_name'])
    plain_lines(@company['address'])
    @pdf.move_down 10
    highlighted(@template.text(:bank_heading))
    plain_lines(@company['bank_details'])
  end

  def bold_line(text)
    @pdf.text(clean(text), style: :bold) if text.present?
  end

  def highlighted(text)
    return if text.blank?

    text = clean(text)
    width = @pdf.width_of(text, style: :bold)
    height = @pdf.font.height
    @pdf.fill_color(Outsider::Crm::ProposalPdf::HIGHLIGHT)
    @pdf.fill_rectangle([0, @pdf.cursor], width + 2, height)
    @pdf.fill_color('000000')
    @pdf.text(text, style: :bold)
  end

  def plain_lines(text)
    text.to_s.split("\n").each { |line| @pdf.text(clean(line)) }
  end

  def signatures
    @pdf.start_new_page if @pdf.cursor < 160
    top = @pdf.cursor
    left = 125
    @pdf.bounding_box([0, top - 20], width: left) { signer_block }
    box_x = left + 12
    box_width = @pdf.bounds.width - box_x
    @pdf.bounding_box([box_x + 8, top - 8], width: box_width - 16) { acceptance_text }
    bottom = @pdf.cursor - 6
    @proposal.sale? ? @pdf.dash(3, space: 2) : @pdf.undash
    @pdf.stroke_rectangle([box_x, top], box_width, top - bottom)
    @pdf.undash
    @pdf.move_cursor_to(bottom)
  end

  def signer_block
    @pdf.text('Atenciosamente,', align: :center)
    @pdf.move_down 24
    @pdf.stroke_horizontal_rule
    @pdf.move_down 4
    @proposal.signer.values_at('name', 'title', 'phone').compact_blank.each { |line| @pdf.text(clean(line), align: :center) }
  end

  def acceptance_text
    rich(@template.text(:signature_box), size: 10)
    @pdf.move_down 12
    @pdf.text('Ass: ______________________________________', size: 10)
    @pdf.move_down 10
    @pdf.text('Nome / Dep.: ______________________________', size: 10)
    @pdf.move_down 10
    stamp = "<color rgb='#{Outsider::Crm::ProposalPdf::BLUE}'><b>* CARIMBO DO CNPJ *</b></color>"
    @pdf.text("Data:          _______ / _______ / _______          #{stamp}", inline_format: true, size: 10)
  end

  def notes
    return if @proposal.notes.blank?

    @pdf.move_down 24
    @pdf.text('Observações', style: :bold)
    @pdf.move_down 4
    rich(@proposal.notes)
  end
end
