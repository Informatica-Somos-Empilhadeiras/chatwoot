# OUTSIDER: segurança da ponte com o Microsoft Teams (Entrega 26).
#
# Entrada: cada mensagem do Teams chega assinada pelo Bot Framework (JWT RS256). verify! confere a assinatura com as
# chaves públicas da Microsoft (guardadas por 1 dia), o emissor, o público (o app_id do robô), a validade, o canal
# (msteams) e se o serviceUrl da mensagem é o do token. Sem isso a mensagem é recusada.
# Saída: token do robô para falar com o Bot Connector (client credentials no Microsoft Entra ID), guardado até perto de
# vencer. O token só é mandado para endereços da Microsoft (microsoft_host?).
class Outsider::Teams::Auth
  class Invalid < StandardError; end

  OPENID = 'https://login.botframework.com/v1/.well-known/openidconfiguration'.freeze
  ISSUER = 'https://api.botframework.com'.freeze
  SCOPE = 'https://api.botframework.com/.default'.freeze
  KEYS_CACHE = 'outsider_teams_openid_keys'.freeze
  LEEWAY = 300
  TIMEOUT = 10
  MICROSOFT_HOSTS = /(\A|\.)(trafficmanager\.net|botframework\.com|botframework\.us|teams\.microsoft\.com|teams\.microsoft\.us|skype\.com)\z/

  def self.microsoft_host?(url)
    uri = URI.parse(url.to_s)
    uri.is_a?(URI::HTTPS) && uri.host.to_s.match?(MICROSOFT_HOSTS)
  rescue URI::InvalidURIError
    false
  end

  def initialize(connection)
    @connection = connection
  end

  def verify!(authorization, activity)
    token = authorization.to_s[/\ABearer (.+)\z/, 1]
    raise Invalid, 'missing token' if token.blank?

    claims, header = decode(token)
    endorsements = Array(keys[header['kid']]&.dig('endorsements'))
    raise Invalid, 'channel' if endorsements.any? && endorsements.exclude?(activity['channelId'])
    raise Invalid, 'service url' if claims['serviceurl'].present? && claims['serviceurl'] != activity['serviceUrl']
    raise Invalid, 'service host' unless self.class.microsoft_host?(activity['serviceUrl'])

    claims
  end

  # token do robô para o Bot Connector
  def access_token
    Rails.cache.fetch("outsider_teams_token:#{@connection.id}:#{@connection.updated_at.to_i}", expires_in: 50.minutes) do
      response = HTTParty.post("https://login.microsoftonline.com/#{@connection.tenant_id}/oauth2/v2.0/token",
                               body: { grant_type: 'client_credentials', client_id: @connection.app_id,
                                       client_secret: @connection.app_password, scope: SCOPE },
                               timeout: TIMEOUT)
      raise Invalid, "token #{response.code}: #{response.parsed_response.try(:dig, 'error')}" unless response.success?

      response.parsed_response['access_token']
    end
  end

  private

  def decode(token)
    claims, header = JWT.decode(token, nil, true, algorithms: ['RS256'], iss: ISSUER, verify_iss: true, aud: @connection.app_id,
                                                  verify_aud: true, leeway: LEEWAY) do |jwt_header|
      key = keys[jwt_header['kid']] || refreshed_keys[jwt_header['kid']]
      raise Invalid, 'unknown key' unless key

      JWT::JWK.import(key.except('endorsements')).public_key
    end
    [claims, header]
  rescue JWT::DecodeError => e
    raise Invalid, e.message
  end

  # chave nova (a Microsoft troca as chaves de tempos em tempos): busca a lista de novo, uma vez
  def refreshed_keys
    return {} if @refreshed

    @refreshed = true
    Rails.cache.delete(KEYS_CACHE)
    @keys = nil
    keys
  end

  # { kid => jwk } das chaves de assinatura do Bot Framework
  def keys
    @keys ||= Rails.cache.fetch(KEYS_CACHE, expires_in: 1.day) do
      jwks_uri = HTTParty.get(OPENID, timeout: TIMEOUT).parsed_response.fetch('jwks_uri')
      HTTParty.get(jwks_uri, timeout: TIMEOUT).parsed_response.fetch('keys').index_by { |key| key['kid'] }
    end
  end
end
