# OUTSIDER: avisos entre os telefones durante o sussurro (Entrega 26), entregues só à pessoa certa pelo canal ao
# vivo do CRM (Outsider::Crm::UpdatesChannel filtra por to_user_id). O servidor confere cada aviso antes de
# repassar:
#
#   invite          atendente -> colega: convite para sussurrar na ligação (vale 2 minutos, uma vez)
#   invite_declined colega -> atendente: recusou o convite
#   request_mode    quem sussurra -> atendente: open (o cliente passa a ouvir) ou whisper (volta a só os atendentes).
#                   Do supervisor, ou para voltar ao sussurro, vira apply_mode (o telefone do atendente obedece);
#                   do convidado querendo falar com o cliente, vira mode_request (o atendente permite ou não)
#   mode            atendente -> quem sussurra: como ficou (open ou whisper) e se o pedido foi aceito
#
# A monitoria em silêncio (modo fantasma) nunca passa por aqui: o atendente não recebe nada dela.
class Outsider::Voice::Signals
  class Refused < StandardError; end

  TYPES = %w[invite invite_declined request_mode mode].freeze
  MODES = %w[open whisper].freeze

  def initialize(settings, user)
    @settings = settings
    @account = settings.account
    @user = user
  end

  def deliver(type:, to_user_id:, data: {})
    to_user_id = to_user_id.to_i
    raise Refused, 'type' unless TYPES.include?(type)
    raise Refused, 'extension' unless @settings.agent_for(@user.id) && @settings.agent_for(to_user_id) && to_user_id != @user.id

    send(type, to_user_id, data.to_h.stringify_keys)
  end

  private

  def invite(guest_id, data)
    Redis::Alfred.setex(Outsider::Voice::MonitorAccess.invite_key(@account.id, @user.id, guest_id), '1', Outsider::Voice::MonitorAccess::INVITE_TTL)
    relay(guest_id, 'invite', customer: data['customer'].to_s.first(80), extension: @settings.agent_for(@user.id)['extension'])
  end

  def invite_declined(host_id, _data)
    relay(host_id, 'invite_declined')
  end

  def request_mode(host_id, data)
    mode = mode_of(data)
    monitor = running_monitor(@user.id, host_id)
    if mode == 'whisper' || monitor.kind == 'supervisor'
      monitor.update!(opened_at: monitor.opened_at || Time.current) if mode == 'open'
      relay(host_id, 'apply_mode', mode: mode, kind: monitor.kind)
    else
      relay(host_id, 'mode_request')
    end
  end

  def mode(whisperer_id, data)
    mode = mode_of(data)
    monitor = running_monitor(whisperer_id, @user.id)
    monitor.update!(opened_at: monitor.opened_at || Time.current) if mode == 'open'
    relay(whisperer_id, 'mode', mode: mode, approved: ActiveModel::Type::Boolean.new.cast(data['approved']) != false)
  end

  def mode_of(data)
    MODES.include?(data['mode']) ? data['mode'] : raise(Refused, 'mode')
  end

  def running_monitor(whisperer_id, host_id)
    Outsider::Voice::Monitor.running.where(account_id: @account.id, user_id: whisperer_id, target_user_id: host_id, mode: 'whisper')
                            .order(started_at: :desc).first || raise(Refused, 'monitor')
  end

  def relay(to_user_id, type, **data)
    Outsider::Crm::LiveUpdates.broadcast(@account.id, 'voice_signal', to_user_id: to_user_id,
                                                                      signal: data.merge(type: type, from: { id: @user.id, name: @user.name }))
  end
end
