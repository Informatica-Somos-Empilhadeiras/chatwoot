# OUTSIDER: a conexão com o Nextcloud onde o escritório guarda as notas fiscais em PDF (Outsider::Erp::NextcloudInvoices):
# endereço (https), usuário, senha de app e a pasta de cada unidade. A senha fica criptografada (Outsider::Bot::Secrets)
# e nunca volta para a tela, como o x-device-id. Parte do Outsider::Erp::Settings.
module Outsider::Erp::Settings::Nextcloud
  NEXTCLOUD_USER = /\A[\w.@+-]{1,100}\z/
  NEXTCLOUD_DEFAULTS = { 'nextcloud_url' => '', 'nextcloud_user' => '', 'nextcloud_secret' => nil, 'nextcloud_folders' => {} }.freeze

  def nextcloud_url = data['nextcloud_url'].to_s
  def nextcloud_user = data['nextcloud_user'].to_s
  def nextcloud_folders = data['nextcloud_folders'].to_h.slice(*companies)
  def nextcloud_password = Outsider::Bot::Secrets.load(data['nextcloud_secret']).to_h['password'].to_s
  def nextcloud_enabled? = enabled? && nextcloud_url.present? && nextcloud_user.present? && nextcloud_password.present? && nextcloud_folders.any?

  private

  def clean_nextcloud(params)
    {
      'nextcloud_url' => clean_nextcloud_url(params.fetch('nextcloud_url', nextcloud_url)),
      'nextcloud_user' => clean_nextcloud_user(params.fetch('nextcloud_user', nextcloud_user)),
      'nextcloud_secret' => clean_nextcloud_secret(params),
      'nextcloud_folders' => clean_nextcloud_folders(params.fetch('nextcloud_folders', nextcloud_folders), params.fetch('companies', companies))
    }
  end

  # https://nuvem.empresa.com.br (ou com a subpasta da instalação); vazio desliga
  def clean_nextcloud_url(value)
    value = value.to_s.strip.chomp('/')
    return '' if value.empty?

    return value if plain_https?(URI.parse(value))

    @errors << 'nextcloud_url'
    nextcloud_url
  rescue URI::InvalidURIError
    @errors << 'nextcloud_url'
    nextcloud_url
  end

  def plain_https?(uri) = uri.is_a?(URI::HTTPS) && uri.host.present? && [uri.query, uri.fragment, uri.userinfo].all?(&:nil?)

  def clean_nextcloud_user(value)
    value = value.to_s.strip
    return value if value.empty? || value.match?(NEXTCLOUD_USER)

    @errors << 'nextcloud_user'
    nextcloud_user
  end

  # vazio mantém a senha que já estava; clear_nextcloud_password apaga
  def clean_nextcloud_secret(params)
    return nil if params['clear_nextcloud_password'] == true

    password = params['nextcloud_password'].to_s.strip
    return data['nextcloud_secret'] if password.empty?

    Outsider::Bot::Secrets.dump('password' => password.first(200))
  end

  # { 'somosemp' => '/Notas Fiscais/Somos' }: só unidades das Configurações, caminho absoluto sem ".."
  def clean_nextcloud_folders(map, units)
    units = Array(units).map { |unit| unit.to_s.strip.downcase }
    map.to_h.each_with_object({}) do |(company, path), out|
      path = path.to_s.strip.chomp('/')
      next if path.empty?

      units.include?(company.to_s) && valid_folder?(path) ? out[company.to_s] = path : @errors << 'nextcloud_folders'
    end
  end

  def valid_folder?(path)
    path.start_with?('/') && path.length <= 300 && path.split('/').exclude?('..') && !path.match?(/[[:cntrl:]]/)
  end
end
