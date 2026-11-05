# OUTSIDER: como está a central (Entrega 22). A cada sincronização (30 s) ela conta se está registrada na
# operadora e quais ramais estão conectados; fica 5 minutos no Redis. Sem notícia há mais de 90 s, a central
# aparece fora do ar na tela de Configurações.
#
# Entrega 26: a URA só entra com a central pronta para ela (ivr_ready). A central conta a versão dela e se tem os
# programas de áudio (ffmpeg e espeak-ng); a primeira imagem da Entrega 26 não conta, mas já busca a lista de áudios
# da URA (prompts_seen!), o que basta. Central antiga, sem nada disso, toca para os vendedores como sempre: o plano de
# discagem dela não conhece a URA e desligaria a ligação.
class Outsider::Voice::CentralStatus
  TTL = 5.minutes
  ONLINE_FOR = 90.seconds

  def initialize(account)
    @account = account
  end

  def report(registration:, extensions:, version: nil, audio: false)
    Redis::Alfred.setex(key, { at: Time.current.to_i, registration: registration, extensions: extensions, version: version,
                               audio: audio }.to_json, TTL)
  end

  # a central buscou a lista de áudios da URA (Outsider::VoiceCentralController#prompts)
  def prompts_seen!
    Redis::Alfred.setex(prompts_key, '1', TTL)
  end

  # a central tem como falar os áudios da URA (contêiner recriado na Entrega 26 ou depois)
  def ivr_ready?
    to_h[:ivr_ready]
  end

  def to_h
    data = JSON.parse(Redis::Alfred.get(key) || '{}')
    seen_at = data['at'] && Time.zone.at(data['at'])
    {
      online: seen_at.present? && seen_at > ONLINE_FOR.ago, seen_at: seen_at,
      registration: data['registration'], extensions: Array(data['extensions']), version: data['version'],
      ivr_ready: data['audio'] == true || Redis::Alfred.exists?(prompts_key)
    }
  end

  private

  def key
    "outsider_voice_status:#{@account.id}"
  end

  def prompts_key
    "outsider_voice_prompts_seen:#{@account.id}"
  end
end
