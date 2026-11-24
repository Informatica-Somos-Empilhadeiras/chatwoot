# OUTSIDER: endereço assinado (sem sessão) para a tela abrir um arquivo dos aplicativos em <img> ou em Baixar: anexo de
# e-mail do Outlook ou do Gmail. Vale 6 horas e diz de qual ligação é; o arquivo é lido na hora no Microsoft/Google
# (Outsider::AppsFilesController) e nunca fica guardado no Chatwoot.
module Outsider::Apps::FileToken
  PURPOSE = 'outsider_apps_file'.freeze
  PATH = '/outsider/apps/file'.freeze
  EXPIRES = 6.hours

  module_function

  def verifier
    Rails.application.message_verifier(PURPOSE)
  end

  # kind: 'ms_attachment' (Outlook) | 'g_attachment' (Gmail)
  def url(link, kind:, **data)
    token = verifier.generate({ 'l' => link.id, 'k' => kind }.merge(data.transform_keys(&:to_s)), expires_in: EXPIRES)
    "#{PATH}?#{{ t: token }.to_query}"
  end

  def read(token)
    data = verifier.verified(token.to_s)
    data.is_a?(Hash) ? data.stringify_keys : nil
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError, JSON::ParserError
    nil
  end
end
