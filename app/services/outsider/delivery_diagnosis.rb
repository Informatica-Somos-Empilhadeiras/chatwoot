# OUTSIDER: o retrato da conferência de entrega numa caixa (ver Outsider::DeliveryCheck), para descobrir por
# que uma mensagem ficou no relógio: se a conferência está rodando, o que o Chatwoot tem de cada mensagem
# enviada e o que a Evolution tem do mesmo período. Só lê, não muda nada. Os telefones aparecem só com o
# final e os textos só com o começo, para o resultado poder ser copiado e mandado a quem for analisar.
#   bin/rails outsider_delivery:diagnostico              # a última hora
#   bin/rails outsider_delivery:diagnostico MINUTOS=180
class Outsider::DeliveryDiagnosis
  CHECK = Outsider::DeliveryCheck
  SHOWN = 15

  def initialize(inbox, minutes: 60)
    @inbox = inbox
    @since = minutes.minutes.ago
    @api = Outsider::EvolutionApi.new(inbox)
  end

  def lines
    title = "== Caixa \"#{@inbox.name}\" (#{@inbox.id}) · instância #{@api.instance}"
    [title, *setup, *evolution, *chatwoot]
  rescue Outsider::EvolutionApi::Error => e
    [title, *setup, "A Evolution não respondeu: #{[e.code, e.message].uniq.join(' · ')}"]
  end

  private

  def setup
    job = Sidekiq::Cron::Job.find('outsider_delivery_check_job')
    proven = Redis::Alfred.exists?("#{CHECK::KEY}:proven:#{@inbox.id}")
    ["Conferência ligada: #{yes(CHECK.enabled?)} (OUTSIDER_DELIVERY_CHECK=#{ENV.fetch('OUTSIDER_DELIVERY_CHECK', 'sem valor')})",
     "Agendamento no Sidekiq: #{job ? "último disparo #{ago(job.last_enqueue_time)}" : 'NÃO ENCONTRADO: o Sidekiq subiu com o código novo?'}",
     "Já confirmou alguma mensagem nesta caixa (trava de segurança): #{yes(proven)}"]
  end

  def evolution
    started = Time.current
    state = @api.connection_state || 'instância não carregada'
    ["Evolution #{@api.version} · conexão #{state} · respondeu em #{((Time.current - started) * 1000).round} ms",
     "Hora no Chatwoot: #{clock(Time.current)} (as horas das duas listas abaixo precisam bater, com até 10 s de diferença)"]
  end

  def chatwoot
    return ["Nenhuma mensagem enviada desde #{clock(@since)}."] if messages.empty?

    states = messages.map { |message| message.content_attributes[CHECK::STATE] || 'sem conferência' }.tally
    ["Enviadas pelo Chatwoot desde #{clock(@since)}: #{messages.size} (#{states.map { |state, count| "#{state}: #{count}" }.join(', ')})",
     *messages.last(SHOWN).map { |message| "  #{message_line(message)}" },
     "Enviadas pela empresa que a Evolution tem do mesmo período: #{records.size}",
     *records.last(SHOWN).map { |record| "  #{record_line(record)}" },
     *addresses]
  end

  def messages
    @messages ||= Message.outgoing.where(account_id: @inbox.account_id, inbox_id: @inbox.id, private: false, created_at: @since..)
                         .includes(:attachments, conversation: :contact).order(:id).to_a
  end

  def records
    @records ||= begin
      range = Outsider::EvolutionApi.timestamp_range(@since - 2.minutes)
      found = @api.find_all_messages({ key: { fromMe: true }, messageTimestamp: range }, page_size: CHECK::PAGE_SIZE)
      found.sort_by { |record| record['messageTimestamp'].to_i }
    end
  end

  def message_line(message)
    webhook = Redis::Alfred.get("#{CHECK::KEY}:webhook:#{message.id}")
    ["##{message.id}", clock(message.created_at), content(message.content, message.attachments.size),
     "conferência=#{message.content_attributes[CHECK::STATE] || '-'}", "situação=#{message.status}",
     "id do WhatsApp=#{message.source_id || '-'}", "webhook=#{webhook ? clock(Time.zone.at(webhook.to_i)) : '-'}",
     "contato=#{mask(chat_id(message.conversation.contact))}"].join(' · ')
  end

  def record_line(record)
    key = record['key'].to_h
    notices = Array(record['MessageUpdate']).pluck('status').join(',')
    [clock(Time.zone.at(record['messageTimestamp'].to_i)), record['messageType'], content(Outsider::WhatsappMessageKey.text_of(record), 0),
     "id=#{key['id']}", "chat=#{mask(key['remoteJid'])}", "outro endereço=#{mask(key['remoteJidAlt'])}",
     "avisos=#{notices.presence || '-'}", "mensagem=#{owner(key['id']) || 'nenhuma'}"].join(' · ')
  end

  # a mensagem do Chatwoot que já está com esse id do WhatsApp
  def owner(id)
    found = messages.find { |message| message.source_id == "WAID:#{id}" || Array(message.content_attributes[CHECK::WA_IDS]).include?(id) }
    "##{found.id}" if found
  end

  # para onde a Evolution manda as mensagens dos contatos que ainda estão sem o id do WhatsApp (até 3)
  def addresses
    contacts = messages.last(SHOWN).select { |message| message.source_id.blank? }.map { |message| message.conversation.contact }
    contacts.uniq.last(3).map do |contact|
      found = @api.whatsapp_numbers([chat_id(contact)]).map { |result| "#{mask(result['jid'])} (no WhatsApp: #{yes(result['exists'])})" }
      "A Evolution manda as mensagens de #{mask(chat_id(contact))} para: #{found.join(', ').presence || 'não respondeu'}"
    end
  end

  def chat_id(contact)
    contact.identifier.presence || contact.phone_number.to_s.delete('^0-9')
  end

  def content(text, attachments)
    parts = []
    parts << "\"#{text.to_s.truncate(13, omission: '…')}\" (#{text.to_s.length} letras)" if text.present?
    parts << "#{attachments} anexo(s)" if attachments.positive?
    parts.join(' + ').presence || 'sem texto'
  end

  # só o final do número e o tipo de endereço: …0001@s.whatsapp.net
  def mask(address)
    return '-' if address.blank?

    name, domain = address.to_s.split('@')
    "…#{name.last(4)}#{"@#{domain}" if domain}"
  end

  def clock(time)
    time.in_time_zone.strftime('%H:%M:%S')
  end

  def ago(time)
    time ? "há #{((Time.current - time) / 60).round} min" : 'nunca'
  end

  def yes(value)
    value ? 'sim' : 'NÃO'
  end
end
