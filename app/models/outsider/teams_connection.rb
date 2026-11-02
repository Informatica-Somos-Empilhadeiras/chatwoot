# OUTSIDER: um robô do Microsoft Teams ligado a uma caixa de entrada do Chatwoot (Entrega 26). O Chatwoot não tem canal
# do Teams (nem nas versões 4.17 a 4.19): a caixa é do tipo API e esta ligação faz a ponte com o Azure Bot Service
# (Outsider::Teams::Inbound recebe, Outsider::Teams::Outbound responde). app_id e tenant_id vêm do registro do robô no
# Azure; a senha (segredo do aplicativo) fica cifrada com a chave do Chatwoot. webhook_token compõe o endereço de
# mensagens que vai no Azure (/outsider/teams/<token>/messages).
class Outsider::TeamsConnection < ApplicationRecord
  self.table_name = 'outsider_teams_connections'

  GUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
  # robô antigo multilocatário usa "botframework.com" no lugar do id do locatário
  TENANT = /\A(\h{8}-\h{4}-\h{4}-\h{4}-\h{12}|botframework\.com)\z/

  belongs_to :account
  belongs_to :inbox

  validates :app_id, format: { with: GUID }
  validates :tenant_id, format: { with: TENANT }
  validates :app_password_encrypted, :webhook_token, presence: true
  validates :inbox_id, uniqueness: true
  validates :webhook_token, uniqueness: true

  before_validation { self.webhook_token ||= SecureRandom.alphanumeric(40) }

  def app_password
    encryptor.decrypt_and_verify(app_password_encrypted.to_s)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    ''
  end

  def app_password=(value)
    self.app_password_encrypted = encryptor.encrypt_and_sign(value.to_s) if value.present?
  end

  def messaging_path
    "/outsider/teams/#{webhook_token}/messages"
  end

  private

  def encryptor
    ActiveSupport::MessageEncryptor.new(Rails.application.key_generator.generate_key('outsider_teams_app_password', 32))
  end
end
