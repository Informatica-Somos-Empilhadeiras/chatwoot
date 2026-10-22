# OUTSIDER: envia contatos como cartão de contato do WhatsApp (vCard), igual ao celular.
#
# O Chatwoot não tem esse tipo de mensagem para a caixa da Evolution: um anexo .vcf chegaria ao
# cliente como arquivo. Então o envio vai direto na Evolution (/message/sendContact) e ela mesma
# registra a mensagem na conversa, como faz com o que sai do celular ("*Contato:* ... _Nome:_ ...",
# source_id WAID:<id>). Esperamos essa mensagem chegar por alguns segundos para colocar quem
# enviou e os dados do cartão (content_attributes.outsider_contacts); se ela demorar mais, o
# cartão aparece do mesmo jeito, lido do texto.
#
# O número de cada contato é conferido no WhatsApp (whatsappNumbers) para o botão "Conversar" do
# cartão abrir a conversa certa, inclusive com o 9º dígito. Número sem WhatsApp vai assim mesmo,
# como no celular (o WhatsApp mostra "Convidar").
class Outsider::ContactCardSender
  class Invalid < StandardError; end

  MAX_CONTACTS = 10
  ECHO_WAIT = 6.seconds
  ECHO_INTERVAL = 0.4

  pattr_initialize [:conversation!, :user!, :contacts!]

  def perform
    raise Invalid, 'not_evolution' unless Outsider::EvolutionApi.evolution_inbox?(conversation.inbox)

    cards = normalized_contacts
    response = api.send_contact(number: recipient, contact: cards.map { |card| vcard_payload(card) })
    message_id = response.dig('key', 'id')
    attach_echo(message_id, cards) if message_id.present?
  end

  private

  def api
    @api ||= Outsider::EvolutionApi.new(conversation.inbox)
  end

  # mesmo destino que a Evolution usa quando a mensagem sai do Chatwoot
  def recipient
    contact = conversation.contact
    contact.identifier.presence || contact.phone_number.to_s.delete('^0-9').presence || raise(Invalid, 'no_recipient')
  end

  def normalized_contacts
    list = Array(contacts).first(MAX_CONTACTS + 1)
    raise Invalid, 'no_contacts' if list.empty?
    raise Invalid, 'too_many_contacts' if list.size > MAX_CONTACTS

    cards = list.map { |contact| normalize(contact.to_h.symbolize_keys) }
    add_whatsapp_ids(cards)
    cards
  end

  def normalize(contact)
    digits = full_number(contact[:phone].to_s.delete('^0-9'))
    name = contact[:name].to_s.squish.first(100)
    raise Invalid, 'invalid_phone' unless digits.length.between?(10, 15)
    raise Invalid, 'missing_name' if name.blank?

    { name: name, phone: digits, email: contact[:email].to_s.strip.presence, company: contact[:company].to_s.squish.first(100).presence }
  end

  # sem o 55: 10 ou 11 dígitos são DDD + número
  def full_number(digits)
    digits.length.between?(10, 11) ? "55#{digits}" : digits
  end

  def add_whatsapp_ids(cards)
    found = api.whatsapp_numbers(cards.pluck(:phone).uniq).select { |result| result['exists'] }
    cards.each do |card|
      match = found.find { |result| result['number'].to_s == card[:phone] }
      card[:waid] = match ? match['jid'].to_s.split('@').first : card[:phone]
    end
  rescue Outsider::EvolutionApi::Error
    cards.each { |card| card[:waid] = card[:phone] }
  end

  def vcard_payload(card)
    {
      fullName: card[:name], wuid: card[:waid], phoneNumber: display_phone(card[:waid]),
      organization: card[:company], email: card[:email]
    }.compact
  end

  # +55 62 99999-0001, como o WhatsApp mostra
  def display_phone(digits)
    match = digits.match(/\A55(\d{2})(\d{4,5})(\d{4})\z/)
    match ? "+55 #{match[1]} #{match[2]}-#{match[3]}" : "+#{digits}"
  end

  def attach_echo(message_id, cards)
    message = wait_for_echo("WAID:#{message_id}")
    return unless message

    message.update!(sender: user, content_attributes: message.content_attributes.merge('outsider_contacts' => cards.map { |card| card_data(card) }))
    message
  end

  def card_data(card)
    card.slice(:name, :waid, :email, :company).merge(phone: display_phone(card[:waid])).compact.stringify_keys
  end

  def wait_for_echo(source_id)
    deadline = ECHO_WAIT.from_now
    loop do
      # sem o cache de consultas da requisição, senão a busca repetida devolve o primeiro nil
      message = Message.uncached { Message.find_by(inbox_id: conversation.inbox_id, source_id: source_id) }
      return message if message || Time.current > deadline

      sleep ECHO_INTERVAL
    end
  end
end
