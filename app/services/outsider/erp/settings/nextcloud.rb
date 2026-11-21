# OUTSIDER: a conexão com o Nextcloud onde o escritório guarda as notas fiscais em PDF (Outsider::Erp::NextcloudInvoices):
# endereço (https), usuário, senha de app e a pasta raiz onde a busca começa (a do Fiscal, com todas as empresas).
# A senha fica criptografada (Outsider::Bot::Secrets) e nunca volta para a tela, como o x-device-id. Parte do
# Outsider::Erp::Settings.
module Outsider::Erp::Settings::Nextcloud
  NEXTCLOUD_USER = /\A[\w.@+-]{1,100}\z/
  NEXTCLOUD_DEFAULTS = { 'nextcloud_url' => '', 'nextcloud_user' => '', 'nextcloud_secret' => nil, 'nextcloud_folder' => '' }.freeze

  def nextcloud_url = data['nextcloud_url'].to_s
  def nextcloud_user = data['nextcloud_user'].to_s
  def nextcloud_folder = data['nextcloud_folder'].to_s
  def nextcloud_password = Outsider::Bot::Secrets.load(data['nextcloud_secret']).to_h['password'].to_s
  def nextcloud_enabled? = enabled? && nextcloud_url.present? && nextcloud_user.present? && nextcloud_password.present? && nextcloud_folder.present?

  private

  def clean_nextcloud(params)
    {
      'nextcloud_url' => clean_nextcloud_url(params.fetch('nextcloud_url', nextcloud_url)),
      'nextcloud_user' => clean_nextcloud_user(params.fetch('nextcloud_user', nextcloud_user)),
      'nextcloud_secret' => clean_nextcloud_secret(params),
      'nextcloud_folder' => clean_nextcloud_folder(params.fetch('nextcloud_folder', nextcloud_folder))
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

  # "/SERVIDOR/Fiscal$": caminho absoluto no Nextcloud, sem ".."
  def clean_nextcloud_folder(value)
    path = value.to_s.strip.chomp('/')
    return path if path.empty? || (path.start_with?('/') && path.length <= 300 && path.split('/').exclude?('..') && !path.match?(/[[:cntrl:]]/))

    @errors << 'nextcloud_folder'
    nextcloud_folder
  end
end
