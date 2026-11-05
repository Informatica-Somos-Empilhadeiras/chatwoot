# OUTSIDER: como está a central (Entrega 22). A cada sincronização (30 s) ela conta se está registrada na
# operadora e quais ramais estão conectados; fica 5 minutos no Redis. Sem notícia há mais de 90 s, a central
# aparece fora do ar na tela de Configurações.
#
# Entrega 26: a central conta também a versão dela e se tem os programas de áudio da URA (ffmpeg e espeak-ng).
# Central antiga (sem esses dados) segue tocando para os vendedores, mas a URA só entra com audio: true.
class Outsider::Voice::CentralStatus
  TTL = 5.minutes
  ONLINE_FOR = 90.seconds
  # versão do contêiner da central desta entrega (deploy/outsider-voice/entrypoint.sh)
  CURRENT_VERSION = 26

  def initialize(account)
    @account = account
  end

  def report(registration:, extensions:, version: nil, audio: false)
    Redis::Alfred.setex(key, { at: Time.current.to_i, registration: registration, extensions: extensions, version: version,
                               audio: audio }.to_json, TTL)
  end

  # a central tem como falar os áudios da URA (contêiner recriado na Entrega 26 ou depois)
  def ivr_ready?
    to_h[:audio]
  end

  def to_h
    data = JSON.parse(Redis::Alfred.get(key) || '{}')
    seen_at = data['at'] && Time.zone.at(data['at'])
    {
      online: seen_at.present? && seen_at > ONLINE_FOR.ago, seen_at: seen_at,
      registration: data['registration'], extensions: Array(data['extensions']), version: data['version'],
      audio: data['audio'] == true, outdated: data['version'].to_i < CURRENT_VERSION
    }
  end

  private

  def key
    "outsider_voice_status:#{@account.id}"
  end
end
