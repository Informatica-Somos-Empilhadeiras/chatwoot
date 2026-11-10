# OUTSIDER: voz dos textos da URA (Entrega 26). Com a OpenAI configurada no Chatwoot (integração OpenAI da conta ou
# a chave do Captain nas configurações da instalação), o texto vira áudio com voz natural, gerado uma vez quando a
# central busca o áudio (ela guarda o arquivo). Sem a OpenAI, a própria central lê o texto (espeak-ng, voz
# sintética): engine entra no nome do áudio, então ligar a OpenAI depois gera os áudios de novo.
class Outsider::Voice::Speech
  MODEL = 'gpt-4o-mini-tts'.freeze
  ENDPOINT = 'https://api.openai.com'.freeze
  # abaixo dos 15 s do rack-timeout da produção: passando disso o pedido da central era cortado no meio, sem resposta
  TIMEOUT = 12
  INSTRUCTIONS = 'Fale em português do Brasil, com tom cordial, claro e pausado, como numa central de atendimento telefônico.'.freeze

  def initialize(account)
    @account = account
  end

  def available?
    api_key.present?
  end

  def engine
    available? ? 'openai' : 'central'
  end

  # [wav, 'audio/wav'], ou nil se a OpenAI não respondeu (a central tenta de novo na próxima sincronização)
  def synthesize(text, voice)
    response = HTTParty.post("#{endpoint}/v1/audio/speech",
                             headers: { 'Authorization' => "Bearer #{api_key}", 'Content-Type' => 'application/json' },
                             body: { model: MODEL, voice: voice, input: text, instructions: INSTRUCTIONS, response_format: 'wav' }.to_json,
                             timeout: TIMEOUT)
    return [response.body, 'audio/wav'] if response.success?

    Rails.logger.warn("[outsider_voice] speech failed: #{response.code}")
    nil
  rescue StandardError => e
    Rails.logger.warn("[outsider_voice] speech failed: #{e.class}")
    nil
  end

  private

  def api_key
    return @api_key if defined?(@api_key)

    hook = @account.hooks.find_by(app_id: 'openai', status: 'enabled')
    @api_key = hook&.settings&.dig('api_key').presence || InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value.presence
  end

  def endpoint
    (InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value.presence || ENDPOINT).chomp('/')
  end
end
