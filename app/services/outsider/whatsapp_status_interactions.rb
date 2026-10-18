# OUTSIDER: curtidas e respostas dos meus status.
#
# Curtidas: as reações que a Evolution guarda (de qualquer conversa) apontando para o
# status, mais as respostas que são só emoji. Respostas: mensagens do Chatwoot marcadas
# por Outsider::MessageReplyLink, menos as reações que a Evolution já copiou para lá.
class Outsider::WhatsappStatusInteractions
  EMOJI_ONLY = /\A[\p{Extended_Pictographic}\p{Emoji_Modifier}\u{FE0F}\u{200D}\s]+\z/

  def initialize(inbox, api, statuses)
    @inbox = inbox
    @api = api
    @ids = statuses.pluck(:id)
    @since = Time.zone.at(statuses.pluck(:timestamp).min.to_i)
  end

  def for(status_id)
    { reactions: grouped[:reactions][status_id] || [], replies: grouped[:replies][status_id] || [] }
  end

  private

  def grouped
    @grouped ||= if @ids.empty?
                   { reactions: {}, replies: {} }
                 else
                   reactions = evolution_reactions
                   emoji_replies, replies = chatwoot_replies(reactions.pluck(:source_id)).partition do |reply|
                     reply[:content].to_s.strip.match?(EMOJI_ONLY)
                   end
                   reactions += emoji_replies.map { |reply| reply.merge(emoji: reply[:content].strip) }
                   { reactions: reactions.group_by { |reaction| reaction[:status_id] }, replies: replies.group_by { |reply| reply[:status_id] } }
                 end
  end

  def evolution_reactions
    where = { messageType: 'reactionMessage', messageTimestamp: Outsider::EvolutionApi.timestamp_range(@since) }
    records = @api.find_all_messages(where, page_size: 500).select do |record|
      !record.dig('key', 'fromMe') && @ids.include?(record.dig('message', 'reactionMessage', 'key', 'id'))
    end
    people = Outsider::WhatsappStatusPeople.new(@inbox.account, records.flat_map { |record| sender_jids(record) })

    latest_per_person(records).filter_map do |record|
      reaction = record.dig('message', 'reactionMessage')
      next if reaction['text'].blank?

      people.find(sender_jids(record), record['pushName']).merge(
        status_id: reaction.dig('key', 'id'), emoji: reaction['text'], timestamp: record['messageTimestamp'],
        source_id: "WAID:#{record.dig('key', 'id')}"
      )
    end
  end

  # vale a última reação de cada pessoa em cada status; reação vazia é "descurtir"
  def latest_per_person(records)
    records.sort_by { |record| record['messageTimestamp'] }.index_by do |record|
      [record.dig('message', 'reactionMessage', 'key', 'id'), Outsider::WhatsappStatusRecord.preferred_jid(sender_jids(record))]
    end.values
  end

  # content_attributes fica gravado como texto JSON dentro da coluna json, daí o "#>> '{}'"
  def chatwoot_replies(reaction_source_ids)
    messages = @inbox.messages.incoming.where(created_at: @since..)
                     .where("(content_attributes #>> '{}')::jsonb ->> '#{Outsider::MessageReplyLink::ATTRIBUTE}' IN (?)", @ids)
                     .where.not(source_id: reaction_source_ids)
                     .includes(:conversation, :sender)
    messages.filter_map do |message|
      contact = message.sender
      next unless contact.is_a?(Contact)

      Outsider::WhatsappStatusPeople.details(contact).merge(
        status_id: message.content_attributes[Outsider::MessageReplyLink::ATTRIBUTE], content: message.content,
        timestamp: message.created_at.to_i, conversation_id: message.conversation.display_id
      )
    end
  end

  def sender_jids(record)
    Outsider::WhatsappStatusRecord.sender_jids(record)
  end
end
