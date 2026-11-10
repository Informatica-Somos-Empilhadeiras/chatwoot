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
# Quem atende na caixa e os administradores recebem um aviso (push, Outsider::Push::ConnectionNotice), uma
# vez por queda: fora do ar há STUCK_AFTER (presa, ou a Evolution sem responder), desconectada no celular
# (precisa do QR code) e, quando a conexão abre de novo, que voltou e quanto tempo ficou fora.
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

    Outsider::EvolutionApi.inboxes.group_by { |inbox| Outsider::EvolutionApi.new(inbox).instance }.each_value do |inboxes|
      check(Outsider::EvolutionApi.new(inboxes.first), inboxes)
    end
  end

  private

  def check(api, inboxes)
    state = api.connection_state
    return if state.blank?

    if state == 'open'
      came_back(api, inboxes)
      restart_deaf(api, inboxes) if silence.positive?
    else
      recover_stuck(api, state, inboxes)
    end
  rescue Outsider::EvolutionApi::Error => e
    Rails.logger.warn("[Outsider::EvolutionWatchdog] #{api.instance}: Evolution não respondeu (#{e.code}: #{e.message})")
    notify_down(api, inboxes) if minutes_down(api) >= STUCK_AFTER.in_minutes
  end

  def recover_stuck(api, state, inboxes)
    return if minutes_down(api) < STUCK_AFTER.in_minutes
    return reopen(api, inboxes) if state == 'close'

    notify_down(api, inboxes)
    api.restart if act(api, COOLDOWN, "presa em #{state}, reiniciando")
  end

  def reopen(api, inboxes)
    code = api.instance_info&.dig('disconnectionReasonCode')
    if LOGGED_OUT_CODES.include?(code)
      Outsider::Push::ConnectionNotice.new(inboxes).logged_out(code) if first_time?(api, :logged_out_notice)
      # sem ação: a linha no log só se repete a cada COOLDOWN
      return act(api, COOLDOWN, "desconectada no celular (#{code}), precisa ler o QR code")
    end

    notify_down(api, inboxes)
    api.connect if act(api, COOLDOWN, "fechada (#{code || 'sem código'}), abrindo de novo")
  end

  # há quantos minutos a instância está sem conexão; a contagem começa na primeira vez que o vigia vê a queda
  def minutes_down(api)
    Redis::Alfred.set(key(api, :not_open_since), Time.current.to_i, nx: true, ex: 1.day)
    (Time.current.to_i - Redis::Alfred.get(key(api, :not_open_since)).to_i) / 60
  end

  def notify_down(api, inboxes)
    Outsider::Push::ConnectionNotice.new(inboxes).down(minutes_down(api)) if first_time?(api, :down_notice)
  end

  def first_time?(api, name)
    Redis::Alfred.set(key(api, name), 1, nx: true, ex: 1.day)
  end

  # a conexão abriu: quem foi avisado da queda fica sabendo que voltou
  def came_back(api, inboxes)
    since = Redis::Alfred.get(key(api, :not_open_since))
    notified = [:down_notice, :logged_out_notice].sum { |name| Redis::Alfred.delete(key(api, name)).to_i }
    Redis::Alfred.delete(key(api, :not_open_since))
    Outsider::Push::ConnectionNotice.new(inboxes).back((Time.current.to_i - since.to_i) / 60) if since && notified.positive?
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

  def silence
    @silence ||= ENV.fetch('OUTSIDER_EVOLUTION_SILENCE_MINUTES', 30).to_i.minutes
  end

  def key(api, name)
    "#{KEY}:#{api.instance}:#{name}"
  end
end
