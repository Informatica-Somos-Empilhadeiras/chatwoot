# OUTSIDER: um sistema que o bot chama (Configurações > Automação por bot > Conexões), cadastrado uma vez
# e usado pelos blocos. O endereço fica fixo aqui: o que o cliente digita entra só como valor no caminho e
# nunca muda o servidor chamado.
#
#   kind      http: qualquer API (REST/JSON, XML/SOAP, GraphQL, Supabase, webhook do n8n, Make ou Zapier)
#             nextcloud: arquivos do Nextcloud (usuário e senha de app), para os blocos de documento
#             postgres: banco PostgreSQL direto (Supabase, Railway, Neon, Render...), para o bloco Banco de dados
#   auth_type none | header (chave num cabeçalho) | query (chave no endereço) | bearer (token)
#             | basic (usuário e senha) | oauth2 (client credentials: token_url, client_id, client_secret)
#             | headers (vários cabeçalhos com chave: apikey + Authorization do Supabase, Appwrite, Hasura...)
#   secrets   senhas criptografadas (Outsider::Bot::Secrets); a tela nunca recebe o valor, só se está salvo
#   allow_write "permite alterar dados": sem ele os blocos API só consultam e o banco abre só para leitura
class Outsider::Bot::Connection < ApplicationRecord
  KINDS = %w[http nextcloud postgres].freeze
  AUTH_TYPES = %w[none header query bearer basic oauth2 headers].freeze
  SECRET_KEYS = { 'header' => %w[api_key], 'query' => %w[api_key], 'bearer' => %w[token], 'basic' => %w[password],
                  'oauth2' => %w[client_secret], 'headers' => %w[headers] }.freeze
  SETTING_KEYS = %w[header_name query_param username user_id token_url client_id scope client_auth root_folder test_path sslmode].freeze
  HEADER_NAME = /\A[A-Za-z0-9][A-Za-z0-9_-]{0,59}\z/
  BLOCKED_HEADERS = %w[host content-length transfer-encoding connection authorization cookie].freeze
  MAX_HEADERS = 20
  MAX_SECRET_HEADERS = 5

  belongs_to :account

  validates :name, presence: true, length: { maximum: 80 }, uniqueness: { scope: :account_id, case_sensitive: false }
  validates :kind, inclusion: { in: KINDS }
  validates :auth_type, inclusion: { in: AUTH_TYPES }
  validates :timeout_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 30 }
  validate :valid_base_url

  before_validation :normalize

  def nextcloud?
    kind == 'nextcloud'
  end

  def postgres?
    kind == 'postgres'
  end

  # nil quando a senha guardada não abre (ver Outsider::Bot::Secrets)
  def secret_values
    @secret_values = nil if @secrets_source != secrets
    @secrets_source = secrets
    @secret_values ||= Outsider::Bot::Secrets.load(secrets) || {}
  end

  def secrets_unreadable?
    secrets.present? && Outsider::Bot::Secrets.load(secrets).nil?
  end

  def secret(key)
    secret_values[key.to_s].presence
  end

  # o que veio da tela: campo em branco mantém a senha que já estava guardada
  def secret_input=(values)
    current = secrets_unreadable? ? {} : secret_values.dup
    values.to_h.each do |key, value|
      key = key.to_s
      next unless needed_secret_keys.include?(key)

      if key == 'headers'
        current['headers'] = merge_secret_headers(current['headers'].to_h, value)
      elsif value.present?
        current[key] = value.to_s.strip
      end
    end
    write_secrets(current)
  end

  def needed_secret_keys
    nextcloud? || postgres? ? %w[password] : SECRET_KEYS[auth_type] || []
  end

  # cabeçalhos com chave (auth_type headers): { 'apikey' => '...', 'Authorization' => 'Bearer ...' }
  def secret_headers
    secret_values['headers'].to_h
  end

  # "postgresql://usuario:senha@host:5432/banco?sslmode=require", como o Supabase e o Railway mostram
  def connection_string=(value)
    parsed = Outsider::Bot::ConnectionString.parse(value)
    @invalid_connection_string = parsed.nil?
    return unless parsed

    self.kind = 'postgres'
    self.base_url = parsed[:base_url]
    self.settings = settings.to_h.merge('username' => parsed[:username], 'sslmode' => parsed[:sslmode])
    # o Supabase mostra a string com [YOUR-PASSWORD] no lugar da senha
    @placeholder_password = parsed[:password].match?(/YOUR[-_ ]?PASSWORD/i)
    self.secret_input = { 'password' => parsed[:password] } unless @placeholder_password
  end

  # o que veio da tela: troca só os campos editáveis; trocar o usuário do Nextcloud esquece o id descoberto
  def settings_input=(values)
    values = values.respond_to?(:to_unsafe_h) ? values.to_unsafe_h : values.to_h
    given = values.stringify_keys.slice(*(SETTING_KEYS - ['user_id']))
    merged = settings.to_h.merge(given)
    merged.delete('user_id') if given.key?('username') && given['username'].to_s.strip != settings.to_h['username'].to_s
    self.settings = merged
  end

  def api_json
    {
      id: id, name: name, kind: kind, base_url: base_url, auth_type: auth_type, settings: settings, headers: headers,
      timeout_seconds: timeout_seconds, allow_write: allow_write, updated_at: updated_at.to_i,
      secrets_set: needed_secret_keys.index_with { |key| secret(key).present? }, secrets_unreadable: secrets_unreadable?,
      secret_headers: secret_headers.keys
    }
  end

  # endereço para abrir um arquivo no próprio Nextcloud (para o agente, com o login dele)
  def nextcloud_file_url(file_id)
    "#{base_url}/f/#{file_id}" if nextcloud? && file_id.present?
  end

  private

  def write_secrets(values)
    @secret_values = values.slice(*needed_secret_keys)
    self.secrets = Outsider::Bot::Secrets.dump(@secret_values)
    @secrets_source = secrets
  end

  # [{ 'name', 'value' }] da tela: valor em branco mantém o que estava; cabeçalho tirado da lista é apagado
  def merge_secret_headers(current, list)
    list = list.to_unsafe_h if list.respond_to?(:to_unsafe_h)
    list = list.values if list.is_a?(Hash)
    Array(list).first(MAX_SECRET_HEADERS).each_with_object({}) do |item, result|
      item = item.to_h.stringify_keys
      name = item['name'].to_s.strip
      next unless name.match?(HEADER_NAME) && %w[host content-length transfer-encoding connection].exclude?(name.downcase)

      value = item['value'].to_s.gsub(/[\r\n]+/, ' ').strip.first(2000)
      result[name] = value.presence || current[name]
    end.compact
  end

  def normalize
    self.name = name.to_s.squish
    self.kind = 'http' if kind.blank?
    self.auth_type = 'basic' if nextcloud? || postgres?
    self.allow_write = false if nextcloud?
    self.base_url = base_url.to_s.strip.sub(%r{/+\z}, '')
    self.settings = settings.to_h.stringify_keys.slice(*SETTING_KEYS).transform_values { |value| value.to_s.strip.first(500) }
    self.headers = clean_headers(headers)
    write_secrets(secret_values) if auth_type_changed? && !secrets_unreadable?
  end

  def clean_headers(value)
    list = value.is_a?(Array) ? value.map { |item| [item['name'] || item['key'], item['value']] } : value.to_h.to_a
    list.first(MAX_HEADERS).each_with_object({}) do |(key, header_value), result|
      key = key.to_s.strip
      next unless key.match?(HEADER_NAME) && BLOCKED_HEADERS.exclude?(key.downcase)

      result[key] = header_value.to_s.gsub(/[\r\n]+/, ' ').strip.first(500)
    end
  end

  def valid_base_url
    return errors.add(:base_url, I18n.t('outsider_bot.errors.password_placeholder')) if @placeholder_password
    return valid_postgres_url if postgres? || @invalid_connection_string

    uri = URI.parse(base_url.to_s)
    ok = uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?
    errors.add(:base_url, I18n.t('outsider_bot.errors.invalid_base_url')) unless ok
  rescue URI::InvalidURIError
    errors.add(:base_url, I18n.t('outsider_bot.errors.invalid_base_url'))
  end

  def valid_postgres_url
    return if !@invalid_connection_string && Outsider::Bot::ConnectionString.valid_base?(base_url)

    errors.add(:base_url, I18n.t('outsider_bot.errors.invalid_connection_string'))
  end
end
