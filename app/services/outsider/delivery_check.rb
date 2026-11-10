# OUTSIDER: conferência de entrega das mensagens que saem do Chatwoot pela Evolution.
#
# O Chatwoot entrega a mensagem à Evolution por webhook e a Evolution responde "ok" mesmo quando não
# consegue mandar ao WhatsApp. O balão mostrava ✓ na hora, sempre, e sem o celular na mão ninguém sabia
# se a mensagem tinha saído. Agora a mensagem nasce "em conferência" (relógio no balão) e este serviço
# pergunta à Evolution o que aconteceu de verdade:
# - achou a mensagem no WhatsApp: ✓ enviada, ✓✓ entregue no celular do cliente, ✓✓ azul lida;
# - o WhatsApp recusou a mensagem: falha;
# - não achou até o prazo (TEXT_WINDOW, ou MEDIA_WINDOW com arquivo, contado de quando o webhook foi
#   entregue à Evolution): falha, com o aviso para conferir antes de mandar de novo. Se a mensagem
#   aparecer depois, a falha some sozinha.
# A mensagem que o webhook dava como falha só por demora (a Evolution responde depois de mandar, e um
# arquivo grande passa do tempo do webhook) fica no relógio e vira ✓ quando aparece no WhatsApp.
#
# Como acha:
# - a Evolution com acesso ao banco do Chatwoot (CHATWOOT_IMPORT_DATABASE_CONNECTION_URI) grava o id do
#   WhatsApp direto na mensagem (source_id WAID:<id>) assim que envia: é só ver a situação desse id;
# - sem isso, a Evolution não diz qual mensagem do WhatsApp é de qual mensagem do Chatwoot. Entre as
#   enviadas pela empresa no mesmo chat (Outsider::DeliveryChat) que ainda não são de nenhuma mensagem do
#   Chatwoot, vale a de mesmo texto (ou um arquivo para cada anexo); no fim do prazo, a enviada logo depois
#   da mensagem (Outsider::DeliveryMatch). Achada, o id fica no source_id, como nas que vêm do WhatsApp.
#
# Trava de segurança: uma mensagem só é dada como não confirmada na caixa em que a conferência confirmou
# alguma mensagem nos últimos PROVEN_FOR. Se a Evolution deixar de responder do jeito esperado (ou o
# relógio dela estiver mais de Outsider::DeliveryMatch::SKEW atrás do relógio do Chatwoot), as mensagens
# voltam a aparecer como antes (✓ na hora), sem alarme falso.
#
# Roda a cada minuto e logo depois de cada webhook (Outsider::DeliveryCheckJob). Liga sozinho na produção;
# OUTSIDER_DELIVERY_CHECK=false desliga e =true liga em outro ambiente.
class Outsider::DeliveryCheck
  STATE = 'outsider_delivery'.freeze
  CHECKING = 'checking'.freeze
  CONFIRMED = 'confirmed'.freeze
  UNCONFIRMED = 'unconfirmed'.freeze
  # de quando vale procurar: a hora do "Tentar de novo" (segundos); sem ele, a criação da mensagem
  SINCE = 'outsider_delivery_since'.freeze
  # ids do WhatsApp da mensagem com mais de um anexo (cada anexo sai como uma mensagem)
  WA_IDS = 'outsider_wa_ids'.freeze

  TEXT_WINDOW = 2.minutes
  MEDIA_WINDOW = 6.minutes
  # sem registro do webhook (fila do Sidekiq parada), o prazo conta da criação da mensagem
  UNSENT_WINDOW = 15.minutes
  # até quando uma mensagem é conferida; a dada como não confirmada ainda pode aparecer nesse tempo
  PENDING_WINDOW = 1.hour
  # até quando a ✓ enviada é acompanhada para virar ✓✓ entregue (a lida a Evolution avisa por conta própria)
  FOLLOW_WINDOW = 30.minutes
  PROVEN_FOR = 7.days
  SOON = 5.seconds
  SOON_LOCK = 4
  LOCK = 60
  PAGE_SIZE = 200
  # o contato do robô da Evolution: o que vai para ele é comando (/status, /init), não mensagem do WhatsApp
  BOT_PHONE = '+123456'.freeze
  KEY = 'outsider_delivery_check'.freeze

  def self.enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('OUTSIDER_DELIVERY_CHECK', Rails.env.production?)) && Outsider::EvolutionApi.configured?
  end

  # a mensagem que sai pelo webhook da Evolution: do agente ou do bot, sem ser nota interna nem a cópia
  # do que já saiu pelo WhatsApp (essa chega com o source_id)
  def self.tracks?(message)
    message.outgoing? && !message.private? && message.source_id.blank? && enabled? &&
      Outsider::EvolutionApi.evolution_inbox?(message.inbox) && message.conversation.contact.phone_number != BOT_PHONE
  end

  # o webhook da mensagem está indo para a Evolution: o prazo da conferência conta daqui
  def self.webhook_started(message_id)
    Redis::Alfred.setex("#{KEY}:webhook:#{message_id}", Time.current.to_i, PENDING_WINDOW.to_i)
  end

  # confere a caixa daqui a pouco; os webhooks que terminarem nesse meio-tempo entram na mesma conferência
  def self.check_soon(inbox_id)
    return unless Redis::Alfred.set("#{KEY}:soon:#{inbox_id}", 1, nx: true, ex: SOON_LOCK)

    Outsider::DeliveryCheckJob.set(wait: SOON, queue: :medium).perform_later(inbox_id)
  end

  # "Tentar de novo" na mensagem que falhou: ela vai outra vez para a Evolution e a conferência recomeça,
  # valendo só o que sair daqui para a frente
  def self.resend(message)
    return unless enabled? && message.outgoing? && !message.private? && Outsider::EvolutionApi.evolution_inbox?(message.inbox)

    attributes = message.content_attributes.except(STATE, SINCE, WA_IDS)
    attributes = attributes.merge(STATE => CHECKING, SINCE => Time.current.to_i) if message.created_at > (PENDING_WINDOW - UNSENT_WINDOW).ago
    message.update!(source_id: nil, content_attributes: attributes)
    channel = message.inbox.channel
    WebhookJob.perform_later(channel.webhook_url, Outsider::EvolutionApi.message_created_payload(message), :api_inbox_webhook,
                             secret: channel.secret, delivery_id: SecureRandom.uuid)
  end

  def self.since(message)
    message.content_attributes[SINCE] ? Time.zone.at(message.content_attributes[SINCE].to_i) : message.created_at
  end

  def initialize(inbox)
    @inbox = inbox
    @api = Outsider::EvolutionApi.new(inbox)
    @chats = Outsider::DeliveryChat.new(inbox, @api)
  end

  # follow: também acompanha as ✓ enviadas até virarem ✓✓ entregue (a conferência de cada minuto); sem ele,
  # só confirma as que estão em conferência (a de logo depois do envio, que pede menos à Evolution)
  def perform(follow: true)
    return unless self.class.enabled? && Redis::Alfred.set(key(:lock), 1, nx: true, ex: LOCK)

    begin
      check(follow ? waiting + following : waiting)
    rescue Outsider::EvolutionApi::Error => e
      Rails.logger.warn("[Outsider::DeliveryCheck] #{@api.instance}: Evolution não respondeu (#{e.code}: #{e.message})")
    ensure
      Redis::Alfred.delete(key(:lock))
    end
  end

  private

  def check(messages)
    return if messages.empty?

    since = messages.map { |message| self.class.since(message) }.min - Outsider::DeliveryMatch::SKEW
    records = @api.find_all_messages({ key: { fromMe: true }, messageTimestamp: Outsider::EvolutionApi.timestamp_range(since) },
                                     page_size: PAGE_SIZE)
    confirm(records)
    follow(records, messages & following)
  end

  def recent
    @recent ||= Message.outgoing.where(account_id: @inbox.account_id, inbox_id: @inbox.id, private: false, created_at: PENDING_WINDOW.ago..)
                       .includes(:attachments, conversation: :contact).order(:id).to_a
  end

  # em conferência, ou dadas como não confirmadas (ainda podem aparecer)
  def waiting
    @waiting ||= recent.select { |message| [CHECKING, UNCONFIRMED].include?(message.content_attributes[STATE]) }
  end

  # já no WhatsApp com ✓, esperando a ✓✓ (nos grupos o WhatsApp não manda a entrega: ficam com ✓)
  def following
    @following ||= recent.select do |message|
      message.sent? && message.source_id.to_s.start_with?('WAID:') && message.created_at > FOLLOW_WINDOW.ago &&
        !message.conversation.contact.identifier.to_s.end_with?('@g.us')
    end
  end

  def confirm(records)
    linked, loose = waiting.partition { |message| message.source_id.to_s.start_with?('WAID:') }
    confirm_linked(linked, records)
    free = unclaimed(records)
    deadlines = loose.index_by(&:id).transform_values { |message| deadline(message) }
    loose.group_by(&:conversation).each do |conversation, messages|
      found = matches(messages, free, conversation.contact, deadlines)
      free -= found.values.flatten
      messages.each { |message| settle(message, found[message.id], deadlines[message.id]) }
    end
  end

  # A mensagem já está com o id do WhatsApp (a Evolution gravou direto no banco, ou a busca da reação achou):
  # ela saiu, é só ver a situação
  def confirm_linked(messages, records)
    by_id = records.index_by { |record| record.dig('key', 'id') }
    messages.each { |message| confirmed(message, by_id.values_at(message.source_id.delete_prefix('WAID:')).compact) }
    prove if messages.any?
  end

  def matches(messages, free, contact, deadlines)
    match = Outsider::DeliveryMatch.new(messages, @chats.records(free, contact), deadlines)
    found = match.found
    if lost?(messages, found) && @chats.learn(contact)
      match = Outsider::DeliveryMatch.new(messages, @chats.records(free, contact), deadlines)
      found = match.found
    end
    prove if match.exact?
    found
  end

  # já foi entregue à Evolution e não apareceu no chat do contato: ela pode ter mandado para o endereço novo dele
  def lost?(messages, found)
    messages.any? { |message| found[message.id].size < Outsider::DeliveryMatch.wanted(message) && webhook_at(message) }
  end

  # confirmar uma mensagem prova que a conferência funciona nesta caixa (a trava de segurança)
  def prove
    Redis::Alfred.setex(key(:proven), 1, PROVEN_FOR.to_i)
  end

  # as enviadas pela empresa que ainda não são de nenhuma mensagem do Chatwoot, da mais antiga para a mais nova
  def unclaimed(records)
    ids = records.map { |record| record.dig('key', 'id') }
    taken = Message.where(account_id: @inbox.account_id, inbox_id: @inbox.id, source_id: ids.map { |id| "WAID:#{id}" }).pluck(:source_id)
    taken = taken.map { |source_id| source_id.delete_prefix('WAID:') } + recent.flat_map { |message| Array(message.content_attributes[WA_IDS]) }
    records.reject { |record| taken.include?(record.dig('key', 'id')) }.sort_by { |record| record['messageTimestamp'].to_i }
  end

  # quando o webhook da mensagem foi para a Evolution (nil enquanto não foi)
  def webhook_at(message)
    @webhook_at ||= {}
    @webhook_at.fetch(message.id) { @webhook_at[message.id] = Redis::Alfred.get("#{KEY}:webhook:#{message.id}")&.to_i }
  end

  # o prazo conta de quando o webhook foi para a Evolution
  def deadline(message)
    return self.class.since(message) + UNSENT_WINDOW unless webhook_at(message)

    Time.zone.at(webhook_at(message)) + (message.attachments.any? ? MEDIA_WINDOW : TEXT_WINDOW)
  end

  def settle(message, records, deadline)
    return confirmed(message, records) if records.size >= Outsider::DeliveryMatch.wanted(message)
    return unless message.content_attributes[STATE] == CHECKING && deadline.past?

    Redis::Alfred.exists?(key(:proven)) ? unconfirmed(message, records) : release(message)
  end

  def confirmed(message, records)
    ids = records.map { |record| record.dig('key', 'id') }
    status = Outsider::DeliveryStatus.of(message, records)
    attributes = message.content_attributes.except('external_error').merge(STATE => CONFIRMED)
    attributes[WA_IDS] = ids if ids.many?
    attributes['external_error'] = text(:refused) if status == 'failed'
    message.update!(source_id: ids.first ? "WAID:#{ids.first}" : message.source_id, status: status, content_attributes: attributes)
    Outsider::Push::UndeliveredMessage.new(message).perform if status == 'failed'
  end

  def unconfirmed(message, records)
    Rails.logger.warn("[Outsider::DeliveryCheck] #{@api.instance}: mensagem #{message.id} sem confirmação do WhatsApp")
    error = [text(records.any? ? :partial : :unconfirmed), ("(#{message.external_error})" if message.failed? && message.external_error.present?)]
    attributes = message.content_attributes.merge(STATE => UNCONFIRMED, 'external_error' => error.compact.join(' '))
    message.update!(status: :failed, content_attributes: attributes)
    Outsider::Push::UndeliveredMessage.new(message).perform
  end

  def release(message)
    Rails.logger.warn("[Outsider::DeliveryCheck] #{@api.instance}: a conferência ainda não confirmou nenhuma mensagem nesta caixa; " \
                      "a mensagem #{message.id} fica sem conferir")
    message.update!(content_attributes: message.content_attributes.except(STATE, SINCE))
  end

  def follow(records, messages)
    by_id = records.index_by { |record| record.dig('key', 'id') }
    messages.each do |message|
      ids = message.content_attributes[WA_IDS] || [message.source_id.delete_prefix('WAID:')]
      found = by_id.values_at(*ids).compact
      next if found.size < ids.size

      status = Outsider::DeliveryStatus.of(message, found)
      next if status == message.status

      Messages::StatusUpdateService.new(message, status, (text(:refused) if status == 'failed')).perform
      Outsider::Push::UndeliveredMessage.new(message).perform if status == 'failed'
    end
  end

  def text(name)
    I18n.with_locale(@inbox.account.locale) { I18n.t("outsider_delivery.#{name}") }
  end

  def key(name)
    "#{KEY}:#{name}:#{@inbox.id}"
  end
end
