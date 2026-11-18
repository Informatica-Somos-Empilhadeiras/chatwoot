# OUTSIDER (técnicos): os avisos da ligação que acorda o celular (Outsider::Voice::Wake), no formato que o
# public/outsider-push-sw.js entende.
#   ring: "Carlos Souza" / "Ligação de voz · ramal 201 · Vendas SP", foto, Atender e Recusar; toca e vibra de novo a
#         cada poucos segundos até atender, recusar ou a ligação acabar (o service worker repete)
#   stop: tira o aviso (atendida, recusada ou acabada) e deixa no lugar um aviso quieto, sem som ("Ligação atendida"):
#         o Safari do iPhone corta o push de quem recebe aviso sem mostrar nada (3 vezes); o service worker apaga esse
#         aviso quieto sozinho quando o app está aberto na frente
#   missed: tira o aviso e mostra "Ligação perdida · Carlos Souza", com "Ligar de volta"
class Outsider::Push::CallWake
  RING_TTL = 40

  def initialize(account, linkedid, target)
    @account = account
    @linkedid = linkedid
    @target = target
    @settings = Outsider::Voice::Settings.new(account)
    @entry = Outsider::Voice::Wake.new(@settings).entry(linkedid, target)
  end

  def deliver(kind)
    return 0 unless @entry && user

    case kind
    when 'ring' then sender.deliver(ring, ttl: RING_TTL)
    when 'stop' then sender.deliver(stop('Ligação atendida'), ttl: RING_TTL)
    when 'declined' then sender.deliver(stop('Ligação recusada'), ttl: RING_TTL)
    when 'missed' then deliver_missed
    else 0
    end
  end

  private

  def user
    @user ||= @account.users.find_by(id: @entry['user_id'])
  end

  def sender
    Outsider::Push::Sender.new(user)
  end

  def caller_id
    @caller_id ||= @settings.user_id_for_extension(@entry['caller'])
  end

  def caller_user
    @caller_user ||= caller_id && @account.users.find_by(id: caller_id)
  end

  def caller_name
    caller_user&.name.presence || @entry['caller'].presence || 'Ligação'
  end

  # ramal 201 · Vendas SP
  def caller_details
    parts = []
    parts << "ramal #{@entry['caller']}" if caller_user
    parts << @settings.branch_for(caller_id)&.dig('name') if caller_id
    parts.compact.join(' · ')
  end

  def url(tab = nil)
    "#{Outsider::Push.site}/app/accounts/#{@account.id}/meu-telefone#{tab ? "/#{tab}" : ''}"
  end

  def ring
    details = caller_details
    {
      outsider: 1, kind: 'phone', call: 'wake', linkedid: @linkedid, target: @target, tag: 'outsider-call',
      title: caller_name, body: ['Ligação de voz', details.presence].compact.join(' · '), person: caller_name,
      photo: Outsider::Push.absolute(caller_user&.avatar_url.presence), icon: "#{Outsider::Push.site}#{Outsider::Push::ICONS['phone']}",
      badge: "#{Outsider::Push.site}#{Outsider::Push::BADGES['phone']}", url: url,
      token: Outsider::Voice::Wake.token(@account.id, @linkedid, @target, user.id),
      ring_seconds: Outsider::Voice::Wake::WAIT, sent_at: (Time.current.to_f * 1000).to_i,
      answer_label: 'Atender', decline_label: 'Recusar'
    }
  end

  def stop(ended)
    {
      outsider: 1, kind: 'phone', call: 'stop', linkedid: @linkedid, tag: 'outsider-call', ended_title: caller_name,
      ended_body: [ended, caller_details.presence].compact.join(' · '), url: url('recentes'),
      path: url('recentes').sub(Outsider::Push.site, ''), badge: "#{Outsider::Push.site}#{Outsider::Push::BADGES['phone']}",
      icon: "#{Outsider::Push.site}#{Outsider::Push::ICONS['phone']}"
    }
  end

  # um push só (o navegador pede um aviso visível por push): tira o toque e mostra "Ligação perdida"
  def deliver_missed
    return sender.deliver(stop('Ligação não atendida'), ttl: RING_TTL) unless Outsider::PushSetting.wants?(user, @account, 'calls_missed')

    time = Time.current.in_time_zone(@settings.time_zone).strftime('%H:%M')
    body = [caller_details.presence, "às #{time}"].compact.join(' · ')
    missed = Outsider::Push.payload(
      kind: 'phone', title: "Ligação perdida · #{caller_name}", body: body, url: url('recentes'),
      tag: "call-wake-#{@linkedid}", person: caller_name, photo: caller_user&.avatar_url.presence,
      open_label: 'Abrir', call_label: 'Ligar de volta', number: @entry['caller']
    )
    sender.deliver(missed.merge(call: 'stop', linkedid: @linkedid))
  end
end
