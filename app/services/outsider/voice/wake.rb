# OUTSIDER (técnicos): acordar o celular. Quem liga para um ramal sem telefone conectado (o app do Chatwoot fechado
# no celular, ou em segundo plano: no celular o telefone sai da central depois de um tempo escondido) não cai
# direto: a central pergunta aqui (wake), o Chatwoot manda o push de ligação para os aparelhos da pessoa e a central
# segura a ligação tocando enquanto o celular abre e conecta (Wait/DEVICE_STATE no plano de discagem).
#
# O aviso no celular parece o da ligação do WhatsApp: foto, nome, Atender e Recusar (public/outsider-push-sw.js).
# Atender abre o Chatwoot já atendendo; Recusar devolve ocupado para quem ligou; tocar no aviso abre a tela da
# ligação tocando. Quem tocou no aviso ganha mais tempo (o app pode levar uns segundos para abrir no 4G).
# No fim: atendida ou acabada, o aviso some dos aparelhos (stop); ninguém atendeu, vira "Ligação perdida".
#
# Estado em Redis por ligação (2 minutos): { ramal => { user_id, caller, state: wait|accept|decline } }.
class Outsider::Voice::Wake
  WAIT = 25
  ACCEPT_WAIT = 45
  TTL = 2.minutes.to_i
  TOKEN_PURPOSE = 'outsider_push_call'.freeze
  TOKEN_EXPIRES = 3.minutes

  def initialize(settings)
    @settings = settings
    @account = settings.account
  end

  # segundos que a central espera o celular conectar; 0 = ninguém para acordar (sem push ativado, sem telefone no perfil)
  def start(linkedid:, extension:, target:)
    user_id = @settings.user_id_for_extension(target)
    user = user_id && @account.users.find_by(id: user_id)
    return 0 unless user && phone_allowed?(user) && user.notification_subscriptions.browser_push.exists?

    write(linkedid, target, 'user_id' => user.id, 'caller' => extension.to_s, 'state' => 'wait')
    Outsider::Voice::WakeJob.perform_later(@account.id, linkedid.to_s, target.to_s, 'ring')
    WAIT
  end

  # o que a pessoa fez no aviso: wait (nada ainda), accept (tocou para atender: espera mais) ou decline
  def status(linkedid:, target:)
    entry = read(linkedid)[target.to_s]
    return '' unless entry

    entry['state'] == 'accept' ? "accept|#{ACCEPT_WAIT}" : entry['state']
  end

  def respond(linkedid:, target:, action:)
    entry = read(linkedid)[target.to_s]
    return false unless entry && %w[accept decline].include?(action)

    write(linkedid, target, entry.merge('state' => action))
    # recusou num aparelho: o aviso some dos outros
    Outsider::Voice::WakeJob.perform_later(@account.id, linkedid.to_s, target.to_s, 'declined') if action == 'decline'
    true
  end

  # atendida (por quem quer que seja) ou acabada: tira o aviso dos aparelhos; quem foi acordado e não atendeu (nem
  # recusou) recebe "Ligação perdida"
  def finish(linkedid:, answered:)
    entries = read(linkedid)
    return if entries.empty?

    entries.each do |target, entry|
      next if entry['done']

      write(linkedid, target, entry.merge('done' => true))
      next if entry['state'] == 'decline' # o aviso já saiu dos aparelhos ao recusar

      missed = !answered
      Outsider::Voice::WakeJob.perform_later(@account.id, linkedid.to_s, target.to_s, missed ? 'missed' : 'stop')
    end
  end

  def entry(linkedid, target)
    read(linkedid)[target.to_s]
  end

  # token do aviso: Atender e Recusar sem a sessão da pessoa (o service worker não tem)
  def self.token(account_id, linkedid, target, user_id)
    Outsider::Push.verifier(TOKEN_PURPOSE).generate({ 'a' => account_id, 'l' => linkedid, 't' => target, 'u' => user_id },
                                                    expires_in: TOKEN_EXPIRES, purpose: TOKEN_PURPOSE)
  end

  def self.token_data(token)
    Outsider::Push.verifier(TOKEN_PURPOSE).verified(token.to_s, purpose: TOKEN_PURPOSE)
  end

  private

  def phone_allowed?(user)
    account_user = @account.account_users.find_by(user_id: user.id)
    account_user.present? && Outsider::Access.for(account_user).allows?('phone', 'use')
  end

  def key(linkedid)
    "outsider:voice:wake:#{@account.id}:#{linkedid}"
  end

  def read(linkedid)
    Redis::Alfred.with { |conn| conn.hgetall(key(linkedid)) }.transform_values { |value| JSON.parse(value) }
  rescue JSON::ParserError
    {}
  end

  def write(linkedid, target, entry)
    Redis::Alfred.with do |conn|
      conn.hset(key(linkedid), target.to_s, entry.to_json)
      conn.expire(key(linkedid), TTL)
    end
  end
end
