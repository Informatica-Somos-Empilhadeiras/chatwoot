# OUTSIDER: leitura das mensagens de status que a Evolution devolve no findMessages.
module Outsider::WhatsappStatusRecord
  TYPES = {
    'imageMessage' => 'image', 'videoMessage' => 'video', 'audioMessage' => 'audio',
    'conversation' => 'text', 'extendedTextMessage' => 'text'
  }.freeze
  PERSON_JID = /\A\d+@(s\.whatsapp\.net|lid)\z/
  # gravado pela Evolution ajustada a cada pessoa que vê um status meu
  VIEWED = 'VIEWED'.freeze

  module_function

  def serialize(record)
    type = TYPES[record['messageType']]
    return if type.nil?

    message = record['message'] || {}
    content = message[record['messageType']]
    content = {} unless content.is_a?(Hash)
    {
      id: record.dig('key', 'id'),
      type: type,
      text: type == 'text' ? message['conversation'] || content['text'] : content['caption'],
      timestamp: record['messageTimestamp'],
      seconds: content['seconds'],
      thumbnail: thumbnail(content['jpegThumbnail']),
      deleted: deleted?(record)
    }
  end

  # Em status, participant é o autor e remoteJidAlt o mesmo autor no outro formato (número ou LID).
  # Em reações vindas de uma conversa, o autor é o remoteJid.
  def sender_jids(record)
    key = record['key']
    [key['participant'], key['participantAlt'], key['remoteJid'], key['remoteJidAlt']].select { |jid| jid.to_s.match?(PERSON_JID) }.uniq
  end

  def preferred_jid(jids)
    jids.find { |jid| jid.end_with?('@s.whatsapp.net') } || jids.first
  end

  def phone_from(jid)
    "+#{jid.split('@').first}" if jid&.end_with?('@s.whatsapp.net')
  end

  def view_count(record)
    Array(record['MessageUpdate']).count { |update| update['status'] == VIEWED }
  end

  # status apagado pelo autor: a Evolution trata o "apagar" como edição da mensagem original,
  # troca a mensagem por null e grava uma linha EDITED
  def deleted?(record)
    record['message'].nil? || record.dig('key', 'deleted').present? ||
      Array(record['MessageUpdate']).any? { |update| update['status'] == 'EDITED' }
  end

  # a Evolution guarda o jpegThumbnail como base64 ou como objeto { "0": 255, "1": 216, ... }
  def thumbnail(raw)
    return if raw.blank?
    return "data:image/jpeg;base64,#{raw}" if raw.is_a?(String)

    bytes = raw['data'].is_a?(Array) ? raw['data'] : raw.sort_by { |index, _| index.to_i }.map(&:last)
    "data:image/jpeg;base64,#{Base64.strict_encode64(bytes.pack('C*'))}"
  end
end
