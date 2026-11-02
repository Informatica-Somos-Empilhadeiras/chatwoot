# OUTSIDER: pacote do aplicativo do Teams (Entrega 26): manifest.json com o robô e os dois ícones, num .zip para enviar
# no Teams (Aplicativos > Gerenciar seus aplicativos > Carregar um aplicativo) ou no centro de administração. O zip é
# montado aqui mesmo, sem compressão (o Teams aceita), para não depender de outra biblioteca.
class Outsider::Teams::AppPackage
  ICONS = Rails.root.join('lib/outsider/teams')
  MANIFEST_VERSION = '1.17'.freeze
  # assinaturas e versão (2.0) dos cabeçalhos do zip
  LOCAL_HEADER = [0x04034b50, 20].pack('Vv').freeze
  CENTRAL_HEADER = [0x02014b50, 20, 20].pack('Vvv').freeze

  # site: endereço público do Chatwoot (FRONTEND_URL), usado nos links e no domínio do manifesto
  def initialize(connection, site:)
    @connection = connection
    @inbox = connection.inbox
    @site = site.to_s.chomp('/')
  end

  def filename
    "teams-#{@inbox.name.parameterize.presence || 'chatwoot'}.zip"
  end

  def to_zip
    zip('manifest.json' => JSON.pretty_generate(manifest), 'color.png' => ICONS.join('color.png').binread,
        'outline.png' => ICONS.join('outline.png').binread)
  end

  def manifest
    name = @inbox.name.to_s.first(30)
    {
      '$schema' => "https://developer.microsoft.com/en-us/json-schemas/teams/v#{MANIFEST_VERSION}/MicrosoftTeams.schema.json",
      'manifestVersion' => MANIFEST_VERSION, 'version' => '1.0.0', 'id' => @connection.app_id,
      'developer' => { 'name' => @connection.account.name.to_s.first(32), 'websiteUrl' => @site, 'privacyUrl' => @site, 'termsOfUseUrl' => @site },
      'name' => { 'short' => name, 'full' => @inbox.name.to_s.first(100) },
      'description' => { 'short' => I18n.t('outsider_teams.manifest.short', name: name).first(80),
                         'full' => I18n.t('outsider_teams.manifest.full', name: name) },
      'icons' => { 'color' => 'color.png', 'outline' => 'outline.png' }, 'accentColor' => '#1F93FF',
      'bots' => [{ 'botId' => @connection.app_id, 'scopes' => %w[personal team groupChat], 'supportsFiles' => false,
                   'isNotificationOnly' => false }],
      'permissions' => %w[identity messageTeamMembers], 'validDomains' => [URI.parse(@site).host].compact
    }
  end

  private

  # zip "guardado" (método 0): cabeçalho local de cada arquivo, o diretório central e o fim
  def zip(files)
    body = ''.b
    central = ''.b
    files.each do |name, content|
      content = content.b
      crc = Zlib.crc32(content)
      offset = body.bytesize
      common = [0, 0, 0, 0x21, crc, content.bytesize, content.bytesize, name.bytesize, 0].pack('vvvvVVVvv')
      body << LOCAL_HEADER << common << name << content
      central << CENTRAL_HEADER << common << [0, 0, 0, 0, offset].pack('vvvVV') << name
    end
    body + central + [0x06054b50, 0, 0, files.size, files.size, central.bytesize, body.bytesize, 0].pack('VvvvvVVv')
  end
end
