# OUTSIDER: blocos do fim do PDF da proposta: confirmação de pedido, dados bancários e para onde mandar a
# documentação; assinatura do vendedor com o quadro de aceite do cliente; observações da proposta. Parte do
# Outsider::Crm::ProposalPdf.
module Outsider::Crm::ProposalPdf::ClosingPage
  private

  def bank_block(_block)
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
    say(text, bold: true) if text.present?
  end

  # títulos deste bloco saem sempre com destaque amarelo, como nas propostas da Somos
  def highlighted(text)
    say(@fields.apply(text), bold: true, highlight: true) if text.present?
  end

  def plain_lines(text)
    text.to_s.split("\n").each { |line| say(line) }
  end

  def signature_block(_block)
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
    say('Atenciosamente,', align: :center, size: block_size - 1)
    @pdf.move_down 24
    @pdf.stroke_horizontal_rule
    @pdf.move_down 4
    @proposal.signer.values_at('name', 'title', 'phone').compact_blank.each { |line| say(line, align: :center, size: block_size - 1) }
  end

  def acceptance_text
    rich(@template.text(:signature_box))
    @pdf.move_down 12
    say('Ass: ______________________________________')
    @pdf.move_down 10
    say('Nome / Dep.: ______________________________')
    @pdf.move_down 10
    stamp = "<color rgb='#{Outsider::Crm::ProposalPdf::BLUE}'><b>* CARIMBO DO CNPJ *</b></color>"
    write(fragments("Data:          _______ / _______ / _______          #{stamp}"))
  end

  def notes_block(_block)
    return if @proposal.notes.blank?

    say('Observações', bold: true)
    @pdf.move_down 4
    rich(@proposal.notes)
  end
end
