# OUTSIDER: guarda as senhas das conexões do bot (Outsider::Bot::Connection) criptografadas, com uma chave
# tirada da SECRET_KEY_BASE do Chatwoot. Não depende do ACTIVE_RECORD_ENCRYPTION, que não vem ligado.
# Se a SECRET_KEY_BASE mudar (ou a conexão foi salva noutro ambiente), load devolve nil e a tela pede a
# senha de novo.
module Outsider::Bot::Secrets
  PURPOSE = 'outsider bot connection secrets'.freeze

  module_function

  def dump(values)
    values = values.to_h.transform_keys(&:to_s).compact_blank
    values.empty? ? nil : encryptor.encrypt_and_sign(values.to_json)
  end

  # {} quando não há nada guardado; nil quando não dá para abrir
  def load(text)
    return {} if text.blank?

    JSON.parse(encryptor.decrypt_and_verify(text).to_s)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature, JSON::ParserError, ArgumentError
    nil
  end

  def encryptor
    @encryptor ||= ActiveSupport::MessageEncryptor.new(
      Rails.application.key_generator.generate_key(PURPOSE, ActiveSupport::MessageEncryptor.key_len)
    )
  end
end
