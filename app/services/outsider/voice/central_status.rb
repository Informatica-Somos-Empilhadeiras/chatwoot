# OUTSIDER: como está a central (Entrega 22). A cada sincronização (30 s) ela conta se está registrada na
# operadora e quais ramais estão conectados; fica 5 minutos no Redis. Sem notícia há mais de 90 s, a central
# aparece fora do ar na tela de Configurações.
#
# Entrega 26: a URA só entra com a central pronta para ela (ivr_ready). A central conta a versão dela e se tem os
# programas de áudio (ffmpeg e espeak-ng); a primeira imagem da Entrega 26 não conta, mas já busca a lista de áudios
# da URA (prompts_seen!), o que basta. Central antiga, sem nada disso, toca para os vendedores como sempre: o plano de
# discagem dela não conhece a URA e desligaria a ligação.
#
# Entrega 26d: guarda também quando a central buscou o plano de discagem neste Chatwoot (ela busca a cada 30 s, em
# qualquer versão) e mostra a versão da telefonia que está rodando, para conferir se o servidor foi atualizado.
#
# Entrega 26e: o aviso da central guarda a versão do Chatwoot que o recebeu, e o estado do plano de discagem (dialplan)
# é calculado aqui, no relógio do servidor:
#   ok       a central buscou o plano neste Chatwoot nos últimos 2 minutos
#   other    o último aviso dela chegou a outro Chatwoot ligado ao mesmo banco e Redis (o VOICE_URL aponta para lá):
#            é de lá que ela recebe o plano de discagem, o antigo
#   waiting  este Chatwoot acabou de subir e a central ainda não voltou a buscar (ela busca a cada 30 s)
#   missing  a central avisa este Chatwoot, mas não busca o plano aqui (proxy ou cache no caminho)
#
# Entrega 26f: ivr_audio_missing guarda a última ligação em que a URA não entrou porque a central ainda não tinha um
# áudio dela (a ligação tocou para os vendedores); some quando uma ligação entra na URA ou depois de um dia.
class Outsider::Voice::CentralStatus
  TTL = 5.minutes
  AUDIO_MISSING_FOR = 1.day
  ONLINE_FOR = 90.seconds
  DIALPLAN_FRESH = 2.minutes
  # versão da telefonia neste código (Telefonia > Configurações): sobe a cada entrega que muda a central
  TELEPHONY_VERSION = '26f'.freeze
  # aviso de antes deste processo subir (logo depois de atualizar) ainda pode ser do Chatwoot antigo
  LOADED_AT = Time.current

  def initialize(account)
    @account = account
  end

  def report(registration:, extensions:, version: nil, audio: false)
    Redis::Alfred.setex(key, { at: Time.current.to_i, registration: registration, extensions: extensions, version: version,
                               audio: audio, chatwoot: TELEPHONY_VERSION }.to_json, TTL)
  end

  # a central buscou o plano de discagem (Outsider::VoiceCentralController#extensions)
  def dialplan_seen!
    Redis::Alfred.setex(dialplan_key, Time.current.to_i.to_s, TTL)
  end

  # a central buscou a lista de áudios da URA (Outsider::VoiceCentralController#prompts)
  def prompts_seen!
    Redis::Alfred.setex(prompts_key, '1', TTL)
  end

  def ivr_audio_missing!(flow_name)
    Redis::Alfred.setex(audio_missing_key, { at: Time.current.to_i, flow: flow_name }.to_json, AUDIO_MISSING_FOR)
  end

  def ivr_audio_found!
    Redis::Alfred.delete(audio_missing_key)
  end

  # a central tem como falar os áudios da URA (contêiner recriado na Entrega 26 ou depois)
  def ivr_ready?
    to_h[:ivr_ready]
  end

  def to_h
    data = JSON.parse(Redis::Alfred.get(key) || '{}')
    seen_at = data['at'] && Time.zone.at(data['at'])
    dialplan = dialplan_at
    {
      online: seen_at.present? && seen_at > ONLINE_FOR.ago, seen_at: seen_at,
      registration: data['registration'], extensions: Array(data['extensions']), version: data['version'],
      ivr_ready: data['audio'] == true || Redis::Alfred.exists?(prompts_key), dialplan_at: dialplan,
      dialplan: dialplan_state(seen_at, data['chatwoot'], dialplan), chatwoot: data['chatwoot'], telephony_version: TELEPHONY_VERSION,
      ivr_audio_missing: audio_missing
    }
  end

  private

  def dialplan_state(seen_at, chatwoot, dialplan)
    return 'other' if seen_at && seen_at > LOADED_AT && chatwoot != TELEPHONY_VERSION
    return 'ok' if dialplan && dialplan > DIALPLAN_FRESH.ago

    DIALPLAN_FRESH.ago < LOADED_AT ? 'waiting' : 'missing'
  end

  def key
    "outsider_voice_status:#{@account.id}"
  end

  def dialplan_at
    at = Redis::Alfred.get(dialplan_key)
    at && Time.zone.at(at.to_i)
  end

  def dialplan_key
    "outsider_voice_dialplan_seen:#{@account.id}"
  end

  def prompts_key
    "outsider_voice_prompts_seen:#{@account.id}"
  end

  # { at:, flow: } da última ligação em que a URA ficou de fora por falta de áudio na central, ou nil
  def audio_missing
    data = JSON.parse(Redis::Alfred.get(audio_missing_key) || 'null')
    data && { at: Time.zone.at(data['at']), flow: data['flow'] }
  end

  def audio_missing_key
    "outsider_voice_ivr_audio_missing:#{@account.id}"
  end
end
