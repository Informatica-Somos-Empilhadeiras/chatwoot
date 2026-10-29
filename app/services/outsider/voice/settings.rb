# OUTSIDER: configurações da central de telefonia (Entrega 22), em accounts.internal_attributes. São os dados
# que a operadora passa (servidor, usuário, senha, números) e os ramais dos vendedores. A central (Asterisk)
# busca a configuração pronta no Chatwoot (Outsider::Voice::CentralConfig): mudar aqui vale lá em até 30 s.
#
# A senha da operadora fica cifrada com a chave do Chatwoot. A senha de cada ramal não é guardada: sai da
# mesma chave, da conta, do vendedor e do ramal (trocar o ramal troca a senha).
class Outsider::Voice::Settings
  include Outsider::Voice::SettingsExtras

  KEY = 'outsider_voice'.freeze
  STATES = %w[AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO].freeze
  ECHO_EXTENSION = '600'.freeze
  EXTENSION = /\A[1-5]\d{2}\z/
  DIAL_FORMATS = %w[ddd zero_ddd country].freeze
  TRANSPORTS = %w[udp tcp].freeze
  AUTH_MODES = %w[register ip].freeze
  HOST = /\A[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])?\z/i
  IP = %r{\A\d{1,3}(\.\d{1,3}){3}(/\d{1,2})?\z}
  RING_SECONDS = (10..60)
  MAX_NUMBERS = 30

  class Invalid < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = errors
      super(errors.join(', '))
    end
  end

  DEFAULTS = {
    'enabled' => false, 'ws_url' => '', 'public_ip' => '', 'ring_seconds' => 20, 'owner_first' => true, 'dial_format' => 'ddd',
    'time_zone' => 'America/Sao_Paulo', 'recording' => true, 'auto_record' => false, 'recording_days' => 365, 'branches' => [],
    'trunk' => { 'host' => '', 'port' => 5060, 'transport' => 'udp', 'auth' => 'register', 'username' => '', 'auth_username' => '',
                 'ips' => [] },
    'numbers' => [], 'agents' => {}
  }.freeze

  def initialize(account)
    @account = account
  end

  attr_reader :account

  def data
    @data ||= begin
      stored = @account.internal_attributes[KEY].to_h
      DEFAULTS.merge(stored).merge('trunk' => DEFAULTS['trunk'].merge(stored['trunk'].to_h))
    end
  end

  def enabled? = data['enabled'] == true

  def trunk
    data['trunk'].merge('password' => decrypt(data['trunk']['password_encrypted']))
  end

  def trunk_ready?
    trunk['host'].present? && (trunk['auth'] == 'ip' || (trunk['username'].present? && trunk['password'].present?))
  end

  def numbers = data['numbers']

  def number_for(did)
    numbers.find { |row| Outsider::Voice::PhoneNumber.same?(row['number'], did) }
  end

  def number_for_state(state) = numbers.find { |row| row['state'] == state } || numbers.first

  # { user_id (inteiro) => { 'extension', 'state', 'enabled' } } só dos ramais ligados
  def enabled_agents
    data['agents'].select { |_id, agent| agent['enabled'] && agent['extension'].present? }.transform_keys(&:to_i)
  end

  def agent_for(user_id)
    enabled_agents[user_id.to_i]
  end

  def user_id_for_extension(extension)
    enabled_agents.find { |_id, agent| agent['extension'] == extension.to_s }&.first
  end

  def sip_password(user_id, extension)
    OpenSSL::HMAC.hexdigest('SHA256', key('outsider_voice_sip'), "#{@account.id}:#{user_id}:#{extension}")[0, 24]
  end

  # Para a tela (só administrador): a senha da operadora nunca volta, só se ela existe
  def as_json(*)
    data.merge('trunk' => data['trunk'].except('password_encrypted').merge('password_set' => data['trunk']['password_encrypted'].present?),
               'costs' => costs, 'recording_days' => recording_days)
  end

  def update(params)
    params = params.to_h.deep_stringify_keys
    @errors = []
    cleaned = clean(params)
    raise Invalid, @errors if @errors.any?

    store(cleaned)
    self
  end

  private

  # extras primeiro: as filiais limpas valem para o campo filial dos ramais
  def clean(params)
    extras = clean_extras(params)
    {
      'enabled' => boolean(params['enabled']), 'ws_url' => url(params['ws_url']), 'public_ip' => public_ip(params['public_ip']),
      'ring_seconds' => ring_seconds(params['ring_seconds']), 'owner_first' => boolean(params['owner_first']),
      'dial_format' => choice(params['dial_format'], DIAL_FORMATS, 'dial_format'),
      'trunk' => clean_trunk(params['trunk'].to_h), 'numbers' => clean_numbers(Array(params['numbers'])),
      'agents' => clean_agents(params['agents'].to_h)
    }.merge(extras)
  end

  def clean_trunk(trunk)
    {
      'host' => host(trunk['host']), 'port' => port(trunk['port']), 'transport' => choice(trunk['transport'], TRANSPORTS, 'trunk.transport'),
      'auth' => choice(trunk['auth'], AUTH_MODES, 'trunk.auth'), 'username' => trunk['username'].to_s.strip,
      'auth_username' => trunk['auth_username'].to_s.strip, 'ips' => ips(trunk['ips']),
      # senha em branco no formulário: continua a guardada
      'password_encrypted' => trunk['password'].present? ? encrypt(trunk['password'].to_s) : data['trunk']['password_encrypted']
    }
  end

  def clean_numbers(rows)
    @errors << 'numbers' if rows.size > MAX_NUMBERS
    seen = []
    rows.each_with_index.filter_map do |row, index|
      row = row.to_h
      number = Outsider::Voice::PhoneNumber.national(row['number'])
      @errors << "numbers.#{index}.number" if number.nil? || seen.include?(number)
      @errors << "numbers.#{index}.state" unless STATES.include?(row['state'])
      seen << number
      { 'number' => number, 'state' => row['state'], 'label' => row['label'].to_s.strip.first(60) }
    end
  end

  def clean_agents(agents)
    user_ids = @account.account_users.pluck(:user_id)
    extensions = []
    agents.each_with_object({}) do |(user_id, agent), result|
      next @errors << "agents.#{user_id}" unless user_ids.include?(user_id.to_i)

      result[user_id.to_i.to_s] = clean_agent(user_id, agent.to_h, extensions)
    end
  end

  # ramal vazio (desligado) ou de 100 a 599 sem repetir
  def clean_agent(user_id, agent, extensions)
    extension = agent['extension'].to_s.strip
    @errors << "agents.#{user_id}.extension" unless extension.empty? || (extension.match?(EXTENSION) && extensions.exclude?(extension))
    @errors << "agents.#{user_id}.state" if agent['state'].present? && STATES.exclude?(agent['state'])
    extensions << extension
    { 'extension' => extension, 'state' => agent['state'].presence, 'enabled' => boolean(agent['enabled']),
      'branch' => clean_branch_id(agent['branch']) }
  end

  def host(value)
    host = value.to_s.strip.downcase
    @errors << 'trunk.host' if host.present? && !host.match?(HOST)
    host
  end

  def port(value)
    port = Integer(value.presence || 5060, exception: false)
    @errors << 'trunk.port' unless port&.between?(1, 65_535)
    port
  end

  def ips(value)
    ips = Array(value).map { |ip| ip.to_s.strip }.compact_blank.uniq
    @errors << 'trunk.ips' unless ips.all? { |ip| ip.match?(IP) }
    ips
  end

  def url(value)
    value = value.to_s.strip
    @errors << 'ws_url' unless value.empty? || value.match?(%r{\Awss?://[^\s/]+(/\S*)?\z})
    value
  end

  def public_ip(value)
    value = value.to_s.strip
    @errors << 'public_ip' unless value.empty? || (value.match?(IP) && value.exclude?('/'))
    value
  end

  def ring_seconds(value)
    seconds = Integer(value.presence || 20, exception: false)
    @errors << 'ring_seconds' unless seconds && RING_SECONDS.cover?(seconds)
    seconds
  end

  def choice(value, options, field)
    value = value.presence || options.first
    @errors << field unless options.include?(value)
    value
  end

  def boolean(value)
    ActiveModel::Type::Boolean.new.cast(value) || false
  end

  def store(cleaned)
    @account.with_lock do
      # update_columns para não esbarrar nas validações de outros campos da conta
      @account.update_columns(internal_attributes: @account.internal_attributes.merge(KEY => cleaned)) # rubocop:disable Rails/SkipsModelValidations
    end
    @data = nil
  end

  def encrypt(value)
    encryptor.encrypt_and_sign(value)
  end

  def decrypt(value)
    value.present? ? encryptor.decrypt_and_verify(value) : ''
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    ''
  end

  def encryptor
    ActiveSupport::MessageEncryptor.new(key('outsider_voice_trunk'))
  end

  def key(salt)
    Rails.application.key_generator.generate_key(salt, 32)
  end
end
