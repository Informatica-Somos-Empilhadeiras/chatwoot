# OUTSIDER: cliente da Evolution API usado pela página Status do WhatsApp.
#
# A caixa criada pela integração Chatwoot da Evolution tem o webhook
# "<url da evolution>/chatwoot/webhook/<instância>", então a URL e a instância
# saem dali. A chave é a global da Evolution (AUTHENTICATION_API_KEY), em
# EVOLUTION_API_KEY. EVOLUTION_API_URL troca a URL quando este servidor
# alcança a Evolution por outro endereço (ex.: o Dev Container).
class Outsider::EvolutionApi
  include HTTParty

  WEBHOOK_PATTERN = %r{\A(?<base_url>https?://.+?)/chatwoot/webhook/(?<instance>[^/?#]+)}
  # abaixo dos 15 s do rack-timeout da produção, para a página mostrar "a Evolution demorou" e não um erro genérico
  DEFAULT_TIMEOUT = 12
  MAX_PAGES = 20

  class Error < StandardError
    attr_reader :code

    def initialize(code, message = nil)
      @code = code
      super(message || code)
    end
  end

  def self.configured?
    ENV['EVOLUTION_API_KEY'].present?
  end

  def self.evolution_inbox?(inbox)
    inbox.api? && inbox.channel.webhook_url.to_s.match?(WEBHOOK_PATTERN)
  end

  # o fim vai uma hora à frente para não perder mensagens de quem está com o relógio adiantado
  def self.timestamp_range(since)
    { gte: since.iso8601, lte: 1.hour.from_now.iso8601 }
  end

  def initialize(inbox)
    match = inbox.channel.webhook_url.to_s.match(WEBHOOK_PATTERN)
    @base_url = (ENV['EVOLUTION_API_URL'].presence || match[:base_url]).chomp('/')
    @instance = match[:instance]
  end

  # Devolve a instância com ownerJid, profileName e profilePicUrl
  def instance_info
    request do
      self.class.get("#{@base_url}/instance/fetchInstances", query: { instanceName: CGI.unescape(@instance) },
                                                             headers: headers, timeout: DEFAULT_TIMEOUT)
    end.first
  end

  # Devolve { 'total', 'pages', 'currentPage', 'records' }
  def find_messages(where, page:, offset:)
    post("/chat/findMessages/#{@instance}", { where: where, page: page, offset: offset })['messages']
  end

  def find_all_messages(where, page_size:)
    records = []
    (1..MAX_PAGES).each do |page|
      result = find_messages(where, page: page, offset: page_size)
      records.concat(result['records'])
      break if page >= result['pages'].to_i
    end
    records
  end

  # Devolve { 'base64', 'mimetype', ... }
  def media(message_id)
    post("/chat/getBase64FromMediaMessage/#{@instance}", { message: { key: { id: message_id } } })
  end

  def send_status(payload, timeout:)
    post("/message/sendStatus/#{@instance}", payload, timeout: timeout)
  end

  # Envia um ou mais contatos (vCard). Devolve a mensagem enviada, com key.id
  def send_contact(number:, contact:)
    post("/message/sendContact/#{@instance}", { number: number, contact: contact })
  end

  # Envia uma localização (o pin de mapa do WhatsApp). Devolve a mensagem enviada, com key.id
  def send_location(number:, latitude:, longitude:, name: nil, address: nil)
    post("/message/sendLocation/#{@instance}", { number: number, latitude: latitude, longitude: longitude, name: name, address: address }.compact)
  end

  # Devolve [{ 'exists', 'jid', 'number' }]
  def whatsapp_numbers(numbers)
    post("/chat/whatsappNumbers/#{@instance}", { numbers: numbers })
  end

  # As linhas de MessageUpdate de um status (edições e, na Evolution ajustada, quem viu)
  def status_updates(id)
    updates = []
    (1..MAX_PAGES).each do |page|
      result = post("/chat/findStatusMessage/#{@instance}", { where: { remoteJid: 'status@broadcast', id: id }, page: page, offset: 500 })
      updates.concat(result)
      break if result.size < 500
    end
    updates
  end

  # "Ler status" da instância: sem ele a Evolution descarta os status dos contatos. É só um aviso
  # na página, então uma resposta estranha vira nil em vez de derrubar a lista.
  def read_status?
    settings = request { self.class.get("#{@base_url}/settings/find/#{@instance}", headers: headers, timeout: DEFAULT_TIMEOUT) }
    settings['readStatus'] if settings.is_a?(Hash)
  rescue Error
    nil
  end

  # a Evolution ajustada para guardar quem viu tem "outsider" na versão
  def views_supported?
    Rails.cache.fetch("outsider_evolution_views/#{@base_url}", expires_in: 10.minutes) do
      request { self.class.get("#{@base_url}/", headers: headers, timeout: DEFAULT_TIMEOUT) }['version'].to_s.include?('outsider')
    end
  rescue Error
    false
  end

  private

  def post(path, body, timeout: DEFAULT_TIMEOUT)
    request { self.class.post("#{@base_url}#{path}", body: body.to_json, headers: headers, timeout: timeout) }
  end

  def request
    raise Error, 'not_configured' unless self.class.configured?

    response = yield
    return response.parsed_response if response.success?

    Rails.logger.error("[Outsider::EvolutionApi] #{response.request.path} #{response.code}: #{response.body.to_s.first(500)}")
    raise Error.new(response.code == 401 ? 'evolution_unauthorized' : 'evolution_error', error_message(response))
  rescue Net::ReadTimeout
    raise Error, 'evolution_timeout'
  rescue Net::OpenTimeout, Net::WriteTimeout, SocketError, SystemCallError => e
    raise Error.new('evolution_unreachable', e.message)
  end

  def error_message(response)
    message = response.parsed_response.dig('response', 'message') if response.parsed_response.is_a?(Hash)
    Array.wrap(message).flatten.join(', ').presence || "HTTP #{response.code}"
  end

  def headers
    { 'Content-Type' => 'application/json', 'apikey' => ENV.fetch('EVOLUTION_API_KEY') }
  end
end
