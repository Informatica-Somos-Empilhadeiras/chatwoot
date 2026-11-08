# OUTSIDER: cifra os segredos do Teams (segredo do aplicativo, tokens dos colaboradores) com a chave do Chatwoot.
# Valor que não abre (chave trocada, por exemplo) volta vazio, e a tela pede para reconectar.
module Outsider::Teams::Secret
  module_function

  def encrypt(purpose, value)
    encryptor(purpose).encrypt_and_sign(value.to_s)
  end

  def decrypt(purpose, value)
    return '' if value.blank?

    encryptor(purpose).decrypt_and_verify(value.to_s)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    ''
  end

  def encryptor(purpose)
    ActiveSupport::MessageEncryptor.new(Rails.application.key_generator.generate_key("outsider_teams_#{purpose}", 32))
  end
end
