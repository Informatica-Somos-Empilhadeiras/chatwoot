# OUTSIDER: a configuração que a central (Asterisk) busca no Chatwoot a cada 30 s (Entrega 22). pjsip é a
# parte que muda com a tela de Configurações: operadora, ramais e endereços; extensions traz só as variáveis
# do plano de discagem (a lógica fica fixa em deploy/outsider-voice/asterisk/extensions.conf).
class Outsider::Voice::CentralConfig
  TRUNK = 'operadora'.freeze
  PRIVATE_NETS = %w[10.0.0.0/8 172.16.0.0/12 192.168.0.0/16].freeze

  def initialize(settings)
    @settings = settings
  end

  def pjsip
    sections = [header, transports, agents]
    sections << trunk if @settings.trunk_ready?
    sections.flatten.join("\n")
  end

  def extensions
    agents = @settings.enabled_agents.values.map { |agent| "PJSIP/#{agent['extension']}" }
    [header, '[globals]', "ALL_AGENTS=#{agents.join('&')}", "RING_SECONDS=#{@settings.data['ring_seconds']}", ''].join("\n")
  end

  private

  def header
    ['; Gerado pelo Chatwoot (Outsider::Voice::CentralConfig). Nao edite: a central troca este arquivo sozinha.', '']
  end

  def transports
    sections = [section('transport-ws', type: 'transport', protocol: 'ws', bind: '0.0.0.0')]
    sections << section('transport-udp', **sip_transport('udp'))
    sections << section('transport-tcp', **sip_transport('tcp')) if @settings.trunk['transport'] == 'tcp'
    sections
  end

  def sip_transport(protocol)
    ip = @settings.data['public_ip']
    options = { type: 'transport', protocol: protocol, bind: '0.0.0.0:5060' }
    options.merge!(external_media_address: ip, external_signaling_address: ip, local_net: PRIVATE_NETS) if ip.present?
    options
  end

  # from_domain: o endereço do telefone (ws_url). Sem ele a central usa o nome do servidor nas mensagens ao
  # navegador, e um nome como "vps-15474911.69.6.250.129" não é endereço válido: o navegador descarta a
  # checagem e as ligações para o ramal sem responder.
  def agents
    users = User.where(id: @settings.enabled_agents.keys).index_by(&:id)
    domain = URI(@settings.data['ws_url']).host
    @settings.enabled_agents.map do |user_id, agent|
      extension = agent['extension']
      name = users[user_id]&.name.to_s.delete("\"\r\n").first(40)
      [
        section(extension, type: 'endpoint', transport: 'transport-ws', context: 'from-agents', disallow: 'all', allow: 'opus,alaw,ulaw',
                           webrtc: 'yes', auth: "#{extension}-auth", aors: extension, callerid: "\"#{name}\" <#{extension}>",
                           device_state_busy_at: 1, rtp_timeout: 60, from_domain: domain),
        section("#{extension}-auth", type: 'auth', auth_type: 'userpass', username: extension,
                                     password: @settings.sip_password(user_id, extension)),
        section(extension, type: 'aor', max_contacts: 1, remove_existing: 'yes', qualify_frequency: 30)
      ]
    end
  end

  def trunk
    data = @settings.trunk
    server = "#{data['host']}:#{data['port']}"
    sections = [trunk_endpoint(data), section(TRUNK, type: 'aor', contact: "sip:#{server}", qualify_frequency: 60)]
    sections << section("#{TRUNK}-auth", type: 'auth', auth_type: 'userpass', username: data['auth_username'].presence || data['username'],
                                         password: data['password'])
    sections << registration(data, server) if data['auth'] == 'register'
    sections << section("#{TRUNK}-identify", type: 'identify', endpoint: TRUNK, match: data['ips'].presence || [data['host']])
    sections
  end

  def trunk_endpoint(data)
    options = { type: 'endpoint', transport: "transport-#{data['transport']}", context: 'from-trunk', disallow: 'all', allow: 'alaw,ulaw',
                aors: TRUNK, direct_media: 'no', rtp_symmetric: 'yes', force_rport: 'yes', rewrite_contact: 'yes',
                dtmf_mode: 'rfc4733', send_pai: 'yes', send_rpid: 'yes', from_domain: data['host'] }
    if data['auth'] == 'register'
      options[:outbound_auth] = "#{TRUNK}-auth"
      options[:from_user] = data['username']
    end
    section(TRUNK, **options)
  end

  def registration(data, server)
    section("#{TRUNK}-reg", type: 'registration', transport: "transport-#{data['transport']}", outbound_auth: "#{TRUNK}-auth",
                            server_uri: "sip:#{server}", client_uri: "sip:#{data['username']}@#{server}", contact_user: data['username'],
                            retry_interval: 60, forbidden_retry_interval: 300, expiration: 300, line: 'yes', endpoint: TRUNK)
  end

  # [nome] com uma linha por opção; lista vira várias linhas com a mesma opção (local_net, match). ";" começa
  # comentário no Asterisk: na senha, vai escapado
  def section(name, **options)
    lines = ["[#{name}]"]
    options.each { |option, value| Array(value).each { |item| lines << "#{option}=#{item.to_s.gsub(';') { '\;' }}" } }
    lines << ''
    lines.join("\n")
  end
end
