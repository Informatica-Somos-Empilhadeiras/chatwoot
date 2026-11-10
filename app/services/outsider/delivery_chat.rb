# OUTSIDER: quais mensagens da Evolution são do chat de um contato, na conferência de entrega (ver
# Outsider::DeliveryCheck).
#
# O contato do Chatwoot tem o número (5562...@s.whatsapp.net), mas o WhatsApp vem trocando o número por um
# endereço novo (...@lid). Quando a Evolution conhece o endereço novo de um contato, a mensagem que sai do
# Chatwoot para o número vai para o endereço novo, e é com ele que fica gravada na Evolution: pelo número,
# a conferência não achava a mensagem e ela ficava no relógio. Quando uma mensagem já entregue à Evolution
# não aparece no chat, perguntamos à Evolution para que endereço ela manda as mensagens daquele contato (a
# mesma consulta que ela faz ao enviar) e guardamos a resposta.
class Outsider::DeliveryChat
  # entre uma pergunta e outra sobre o mesmo contato (numa queda, toda mensagem dele fica sem aparecer)
  ASK_EVERY = 10.minutes
  KNOWN_FOR = 30.days
  KEY = 'outsider_delivery_chat'.freeze

  def initialize(inbox, api)
    @inbox = inbox
    @api = api
  end

  # records: as enviadas pela empresa; devolve as do chat do contato
  def records(records, contact)
    known = addresses(contact)
    records.select { |record| Outsider::WhatsappMessageKey.chat?(record, contact) || known.include?(record.dig('key', 'remoteJid')) }
  end

  # os endereços que a Evolution disse usar para o contato
  def addresses(contact)
    JSON.parse(Redis::Alfred.get(key(:addresses, contact)) || '[]')
  end

  # Pergunta à Evolution. Devolve true quando ela usa um endereço que ainda não conhecíamos.
  def learn(contact)
    number = chat_id(contact)
    return false if number.blank? || !Redis::Alfred.set(key(:asked, contact), 1, nx: true, ex: ASK_EVERY.to_i)

    known = addresses(contact)
    found = @api.whatsapp_numbers([number]).filter_map { |result| result['jid'] }
    Redis::Alfred.setex(key(:addresses, contact), (known | found).to_json, KNOWN_FOR.to_i)
    (found - known).any?
  rescue Outsider::EvolutionApi::Error => e
    Rails.logger.warn("[Outsider::DeliveryChat] #{@api.instance}: a Evolution não disse o endereço do contato #{contact.id} (#{e.code})")
    false
  end

  private

  # o destino que a Evolution usa para a mensagem que sai do Chatwoot; o grupo já tem o endereço certo
  def chat_id(contact)
    number = contact.identifier.presence || contact.phone_number.to_s.delete('^0-9')
    number unless number.end_with?('@g.us')
  end

  def key(name, contact)
    "#{KEY}:#{name}:#{@inbox.id}:#{contact.id}"
  end
end
