# OUTSIDER: vigia das conexões da Evolution API, a cada minuto (Outsider::EvolutionWatchdogJob).
#
# O cliente manda a mensagem, ela aparece no WhatsApp do celular, mas não chega na Evolution nem
# no Chatwoot até alguém reiniciar a instância. Isso acontece de dois jeitos:
# - presa: a conexão caiu e ficou em "connecting" ou "close" sem a Evolution conseguir voltar sozinha;
# - surda: a instância aparece conectada, mas o Baileys parou de entregar as mensagens recebidas
#   (Baileys #2491 e Evolution #2647: o websocket segue vivo, então a Evolution não percebe).
# Ao reconectar, o WhatsApp entrega o que ficou pendente e as mensagens aparecem. O vigia faz isso sozinho:
# - presa há STUCK_AFTER: reinicia ("connecting") ou abre de novo ("close"). Quem desconectou o aparelho
#   no celular (LOGGED_OUT_CODES) precisa ler o QR code de novo; aí só fica o aviso no log.
# - surda: nenhuma mensagem recebida nas caixas da instância nos últimos OUTSIDER_EVOLUTION_SILENCE_MINUTES
#   (padrão 30), mesmo com os agentes mandando mensagem em MIN_WAITING conversas ou mais nesse tempo.
#   Reinicia uma vez; para reiniciar de novo precisa de outro período inteiro de silêncio.
# Entre uma ação e outra na mesma instância passa pelo menos COOLDOWN, para não derrubar uma conexão
# que está voltando (reiniciar seguido pode prender a instância em "conflict").
#
# Liga sozinho na produção; OUTSIDER_EVOLUTION_WATCHDOG=false desliga e =true liga em outro ambiente.
# No Dev Container fica desligado: o banco é uma cópia e ele mexeria nas instâncias da produção.
class Outsider::EvolutionWatchdog
  STUCK_AFTER = 3.minutes
  COOLDOWN = 10.minutes
  MIN_WAITING = 3
  # 401 desconectado no celular, 403 banido, 402 e 406: os códigos em que a própria Evolution não reconecta
  LOGGED_OUT_CODES = [401, 402, 403, 406].freeze
  KEY = 'outsider_evolution_watchdog'.freeze

  def self.enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('OUTSIDER_EVOLUTION_WATCHDOG', Rails.env.production?)) &&
      Outsider::EvolutionApi.configured?
  end

  def perform
    return unless self.class.enabled?

    evolution_inboxes.group_by { |inbox| Outsider::EvolutionApi.new(inbox).instance }.each_value do |inboxes|
      check(Outsider::EvolutionApi.new(inboxes.first), inboxes)
    end
  end

  private

  def check(api, inboxes)
    state = api.connection_state
    return if state.blank?

    if state == 'open'
      Redis::Alfred.delete(key(api, :not_open_since))
      restart_deaf(api, inboxes) if silence.positive?
    else
      recover_stuck(api, state)
    end
  rescue Outsider::EvolutionApi::Error => e
    Rails.logger.warn("[Outsider::EvolutionWatchdog] #{api.instance}: Evolution não respondeu (#{e.code}: #{e.message})")
  end

  def recover_stuck(api, state)
    Redis::Alfred.set(key(api, :not_open_since), Time.current.to_i, nx: true, ex: 1.day)
    return if Time.current.to_i - Redis::Alfred.get(key(api, :not_open_since)).to_i < STUCK_AFTER
    return reopen(api) if state == 'close'

    api.restart if act(api, COOLDOWN, "presa em #{state}, reiniciando")
  end

  def reopen(api)
    code = api.instance_info&.dig('disconnectionReasonCode')
    # sem ação: o aviso só se repete a cada COOLDOWN
    return act(api, COOLDOWN, "desconectada no celular (#{code}), precisa ler o QR code") if LOGGED_OUT_CODES.include?(code)

    api.connect if act(api, COOLDOWN, "fechada (#{code || 'sem código'}), abrindo de novo")
  end

  def restart_deaf(api, inboxes)
    recent = Message.where(account_id: inboxes.map(&:account_id).uniq, inbox_id: inboxes.map(&:id), created_at: silence.ago..)
    return if recent.incoming.exists?

    waiting = recent.outgoing.where(private: false).distinct.count(:conversation_id)
    return if waiting < MIN_WAITING
    return unless act(api, [silence, COOLDOWN].max,
                      "conectada mas sem receber nada há #{silence.in_minutes.to_i} min com #{waiting} conversas esperando, reiniciando")

    api.restart
  end

  # a chave da última ação também é a trava: se dois vigias rodarem juntos, só um age
  def act(api, wait, reason)
    return false unless Redis::Alfred.set(key(api, :acted), Time.current.to_i, nx: true, ex: wait)

    Rails.logger.warn("[Outsider::EvolutionWatchdog] #{api.instance}: #{reason}")
    true
  end

  def evolution_inboxes
    Inbox.where(channel_type: 'Channel::Api').includes(:channel).select { |inbox| Outsider::EvolutionApi.evolution_inbox?(inbox) }
  end

  def silence
    @silence ||= ENV.fetch('OUTSIDER_EVOLUTION_SILENCE_MINUTES', 30).to_i.minutes
  end

  def key(api, name)
    "#{KEY}:#{api.instance}:#{name}"
  end
end
