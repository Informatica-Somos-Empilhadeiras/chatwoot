# OUTSIDER: o menu do bot no formato que a Evolution manda ao WhatsApp (ver Outsider::Bot::Sender): a lista, que
# abre pelo botão "Ver opções", ou os botões de resposta rápida, que o cliente escolhe com um toque (o WhatsApp
# mostra até 3 por mensagem). data é o bloco menu com o texto já preenchido.
class Outsider::Bot::EvolutionMenu
  def initialize(api, number)
    @api = api
    @number = number
  end

  def list(data, options)
    @api.send_list(
      number: @number, title: data['title'].to_s, description: data['text'].presence || data['title'].presence || data['button_label'],
      footer_text: data['footer'].to_s, button_text: data['button_label'],
      sections: [{ title: data['title'].presence || data['button_label'], rows: options.map { |option| list_row(option) } }]
    )
  end

  def buttons(data, options)
    @api.send_buttons(
      number: @number, title: data['title'].presence || data['text'], description: (data['title'].present? ? data['text'] : nil),
      footer: data['footer'].presence,
      buttons: options.map { |option| { type: 'reply', displayText: option['label'], id: option['id'] } }
    )
  end

  private

  def list_row(option)
    { title: option['label'], description: option['description'].presence, rowId: option['id'] }.compact
  end
end
