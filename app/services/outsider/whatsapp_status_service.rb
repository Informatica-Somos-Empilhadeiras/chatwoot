# OUTSIDER: dados da página Status do WhatsApp para uma caixa da Evolution API.
#
# A Evolution guarda os status como mensagens de "status@broadcast" (precisa de
# DATABASE_SAVE_DATA_NEW_MESSAGE=true nela) e a integração Chatwoot da Evolution
# ignora essas mensagens, então elas não viram conversas.
#
# - contacts: status dos contatos nas últimas 24h, agrupados por contato
# - mine: meus status no período, com curtidas, respostas e visualizações
# - viewers: quem viu um dos meus status
# - replied_status: o status que o contato respondeu, para mostrar na conversa
# - audience: quem pode receber um status novo (ver Outsider::WhatsappStatusAudience)
#
# Visualizações: só a Evolution ajustada guarda quem viu (linhas VIEWED em MessageUpdate,
# ver /mnt/project-files/status-whatsapp/evolution); nas outras, views vem nil.
class Outsider::WhatsappStatusService
  STATUS_JID = 'status@broadcast'.freeze
  CONTACTS_WINDOW = 24.hours
  Record = Outsider::WhatsappStatusRecord

  def initialize(inbox)
    @inbox = inbox
    @api = Outsider::EvolutionApi.new(inbox)
  end

  def contacts
    records = status_records(since: CONTACTS_WINDOW.ago).reject do |record|
      record.dig('key', 'fromMe') || Record.sender_jids(record).include?(owner_jid)
    end
    people = Outsider::WhatsappStatusPeople.new(@inbox.account, records.flat_map { |record| Record.sender_jids(record) })
    authors = records.group_by { |record| Record.preferred_jid(Record.sender_jids(record)) }.values.filter_map do |author_records|
      author(author_records, people)
    end

    { me: me, read_status: @api.read_status?, authors: authors.sort_by { |author| -author[:last_timestamp] } }
  end

  def mine(since:)
    views = @api.views_supported?
    statuses = status_records(since: since, from_me: true).filter_map do |record|
      Record.serialize(record)&.merge(views: (Record.view_count(record) if views))
    end
    statuses.sort_by! { |status| -status[:timestamp] }
    interactions = Outsider::WhatsappStatusInteractions.new(@inbox, @api, statuses)

    { me: me, statuses: statuses.map { |status| status.merge(interactions.for(status[:id])) } }
  end

  # quem não está nos contatos do Chatwoot vem sem nome (a página mostra o número, ou
  # "Contato sem nome" quando só há o código @lid)
  def viewers(id)
    raise ActiveRecord::RecordNotFound unless status_record!(id).dig('key', 'fromMe')

    jids = @api.status_updates(id).select { |update| update['status'] == Record::VIEWED }.pluck('participant').compact.uniq
    people = Outsider::WhatsappStatusPeople.new(@inbox.account, jids)
    jids.map do |jid|
      person = people.find([jid], nil)
      person[:contact_id] ? person : person.merge(name: nil)
    end
  end

  def media(id)
    status_record!(id)
    @api.media(id)
  end

  def replied_status(id)
    Record.serialize(status_record!(id)) || raise(ActiveRecord::RecordNotFound)
  end

  def audience
    @audience ||= Outsider::WhatsappStatusAudience.new(@inbox, @api)
  end

  def owner_jid
    instance_info['ownerJid']
  end

  # o navegador manda as quebras de linha do formulário como \r\n
  def text_payload(text, background_color, font)
    { type: 'text', content: text.gsub("\r\n", "\n"), backgroundColor: background_color, font: font }
  end

  def media_payload(type, content_type, data, caption)
    { type: type, content: "data:#{content_type};base64,#{Base64.strict_encode64(data)}", caption: caption.to_s.gsub("\r\n", "\n").presence }.compact
  end

  def republish_payload(id, background_color)
    record = status_record!(id)
    raise ActiveRecord::RecordNotFound unless record.dig('key', 'fromMe')

    status = Record.serialize(record)
    return text_payload(status[:text], background_color, 1) if status[:type] == 'text'
    raise Outsider::EvolutionApi::Error, 'unsupported_type' unless %w[image video].include?(status[:type])

    media = @api.media(id)
    media_payload(status[:type], media['mimetype'], Base64.decode64(media['base64']), status[:text])
  end

  def publish(payload, timeout:)
    @api.send_status(payload, timeout: timeout)
  end

  private

  def instance_info
    @instance_info ||= @api.instance_info
  end

  def me
    { name: instance_info['profileName'], avatar_url: instance_info['profilePicUrl'] }
  end

  def author(records, people)
    statuses = records.filter_map { |record| Record.serialize(record) }.reject { |status| status[:deleted] }
    return if statuses.empty?

    jids = records.flat_map { |record| Record.sender_jids(record) }.uniq
    push_name = records.pluck('pushName').find { |name| name.to_s.match?(/\D/) }
    people.find(jids, push_name)
          .merge(statuses: statuses.sort_by { |status| status[:timestamp] }, last_timestamp: statuses.pluck(:timestamp).max)
  end

  def status_records(since:, from_me: false)
    key = { remoteJid: STATUS_JID }
    key[:fromMe] = true if from_me
    @api.find_all_messages({ key: key, messageTimestamp: Outsider::EvolutionApi.timestamp_range(since) }, page_size: 100)
  end

  def status_record!(id)
    @api.find_messages({ key: { id: id, remoteJid: STATUS_JID } }, page: 1, offset: 1)['records'].first ||
      raise(ActiveRecord::RecordNotFound)
  end
end
