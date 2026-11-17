# OUTSIDER: foto do perfil das pessoas do Teams (chats, canais, sugestões de @, encaminhar, "Meu Teams").
# O navegador recebe um endereço assinado (/outsider/teams/photo, Outsider::TeamsPhotosController); o Chatwoot busca a
# foto na Microsoft com o token de quem está vendo (permissão User.ReadBasic.All) e guarda no Redis por 1 dia.
# Sem foto (ou sem a permissão ainda: antes do "Entrar de novo"), o endereço dá 404 e aparecem as iniciais.
class Outsider::Teams::Graph::Photo
  PATH = '/outsider/teams/photo'.freeze
  PURPOSE = 'outsider_teams_photo'.freeze
  SIZE = '96x96'.freeze
  MAX = 300.kilobytes
  CACHE_TTL = 1.day.to_i
  NO_PHOTO_TTL = 6.hours.to_i
  # sem permissão / Microsoft fora: tenta de novo logo
  RETRY_TTL = 20.minutes.to_i
  ID = /\A[0-9a-f-]{36}\z/i

  # o endereço muda só de hora em hora (o navegador reaproveita a foto que já baixou)
  def self.url(link, ms_id)
    return nil if link.nil? || !ID.match?(ms_id.to_s)

    token = verifier.generate({ 'l' => link.id, 'u' => ms_id.to_s }, expires_at: Time.current.beginning_of_hour + 13.hours)
    "#{PATH}?t=#{token}"
  end

  def self.read(token)
    data = verifier.verified(token.to_s)
    data.is_a?(Hash) && ID.match?(data['u'].to_s) ? data : nil
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError, JSON::ParserError
    nil
  end

  def self.verifier
    ActiveSupport::MessageVerifier.new(Rails.application.key_generator.generate_key(PURPOSE), url_safe: true, digest: 'SHA256',
                                                                                              serializer: JSON)
  end

  def initialize(link)
    @link = link
  end

  # { body:, content_type: } ou nil (sem foto)
  def fetch(ms_id)
    key = "outsider_teams_photo:#{@link.account_id}:#{ms_id}"
    cached = Redis::Alfred.get(key)
    return decode(cached) if cached

    photo = download(ms_id)
    Redis::Alfred.setex(key, photo ? encode(photo) : '-', photo ? CACHE_TTL : NO_PHOTO_TTL)
    photo
  rescue Outsider::Teams::Graph::Client::Error => e
    Rails.logger.info("[outsider_teams_photo] #{ms_id}: #{e.message}")
    Redis::Alfred.setex(key, '-', RETRY_TTL) unless e.is_a?(Outsider::Teams::Graph::Client::Reconnect)
    nil
  end

  private

  # 96x96 primeiro; quem não tem esse tamanho (conta sem caixa do Exchange) cai na foto padrão; 404 nas duas = sem foto
  def download(ms_id)
    client = Outsider::Teams::Graph::Client.new(@link)
    base = "https://graph.microsoft.com/v1.0/users/#{ms_id}"
    get_photo(client, "#{base}/photos/#{SIZE}/$value") || get_photo(client, "#{base}/photo/$value")
  end

  def get_photo(client, url)
    client.bytes(url, max: MAX)
  rescue Outsider::Teams::Graph::Client::Error => e
    raise unless e.status.to_i == 404

    nil
  end

  def encode(photo)
    "#{photo[:content_type]}|#{Base64.strict_encode64(photo[:body])}"
  end

  def decode(value)
    return nil if value == '-'

    type, body = value.split('|', 2)
    { content_type: type, body: Base64.strict_decode64(body.to_s) }
  rescue ArgumentError
    nil
  end
end
