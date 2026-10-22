# OUTSIDER: envia uma localização pelo WhatsApp (o pin de mapa que o cliente toca e abre no Maps).
#
# Como o cartão de contato (Outsider::ContactCardSender), o envio vai direto na Evolution
# (/message/sendLocation) e ela mesma registra a mensagem na conversa como texto
# ("*Localização:* ... _Latitude:_ ... _Longitude:_ ..."). Esperamos essa mensagem por alguns
# segundos para colocar quem enviou e os dados do local (content_attributes.outsider_location);
# se ela demorar mais, o mapa aparece do mesmo jeito, lido do texto.
class Outsider::LocationSender
  class Invalid < StandardError; end

  ECHO_WAIT = 6.seconds
  ECHO_INTERVAL = 0.4

  pattr_initialize [:conversation!, :user!, :location!]

  def perform
    raise Invalid, 'not_evolution' unless Outsider::EvolutionApi.evolution_inbox?(conversation.inbox)

    place = normalized
    response = Outsider::EvolutionApi.new(conversation.inbox).send_location(number: recipient, **place)
    message_id = response.dig('key', 'id')
    attach_echo(message_id, place) if message_id.present?
  end

  private

  # mesmo destino que a Evolution usa quando a mensagem sai do Chatwoot
  def recipient
    contact = conversation.contact
    contact.identifier.presence || contact.phone_number.to_s.delete('^0-9').presence || raise(Invalid, 'no_recipient')
  end

  def normalized
    data = location.to_h.symbolize_keys
    latitude = coordinate(data[:latitude], 90)
    longitude = coordinate(data[:longitude], 180)
    raise Invalid, 'invalid_coordinates' if latitude.nil? || longitude.nil?

    { latitude: latitude, longitude: longitude, name: data[:name].to_s.squish.first(100).presence,
      address: data[:address].to_s.squish.first(300).presence }
  end

  def coordinate(value, limit)
    number = Float(value.to_s.tr(',', '.'), exception: false)
    number.round(6) if number&.between?(-limit, limit)
  end

  def attach_echo(message_id, place)
    message = wait_for_echo("WAID:#{message_id}")
    return unless message

    message.update!(sender: user, content_attributes: message.content_attributes.merge('outsider_location' => place.compact.stringify_keys))
    message
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
