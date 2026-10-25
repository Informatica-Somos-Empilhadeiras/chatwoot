# OUTSIDER: como está a central (Entrega 22). A cada sincronização (30 s) ela conta se está registrada na
# operadora e quais ramais estão conectados; fica 5 minutos no Redis. Sem notícia há mais de 90 s, a central
# aparece fora do ar na tela de Configurações.
class Outsider::Voice::CentralStatus
  TTL = 5.minutes
  ONLINE_FOR = 90.seconds

  def initialize(account)
    @account = account
  end

  def report(registration:, extensions:)
    Redis::Alfred.setex(key, { at: Time.current.to_i, registration: registration, extensions: extensions }.to_json, TTL)
  end

  def to_h
    data = JSON.parse(Redis::Alfred.get(key) || '{}')
    seen_at = data['at'] && Time.zone.at(data['at'])
    {
      online: seen_at.present? && seen_at > ONLINE_FOR.ago, seen_at: seen_at,
      registration: data['registration'], extensions: Array(data['extensions'])
    }
  end

  private

  def key
    "outsider_voice_status:#{@account.id}"
  end
end
