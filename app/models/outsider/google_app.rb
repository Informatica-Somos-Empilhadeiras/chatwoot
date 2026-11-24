# OUTSIDER: o aplicativo OAuth da empresa no Google Cloud para o bloco Google dos Aplicativos (um por conta). O TI cria
# uma vez (ID do cliente e chave secreta, tipo "Aplicativo da Web") e cada colaborador só entra com a conta Google dele
# (Outsider::Apps::Google::Login).
class Outsider::GoogleApp < ApplicationRecord
  self.table_name = 'outsider_google_apps'

  CLIENT_ID = /\A[\w.-]+\.apps\.googleusercontent\.com\z/

  belongs_to :account

  validates :client_id, format: { with: CLIENT_ID }
  validates :client_secret_encrypted, presence: true
  validates :account_id, uniqueness: true

  def client_secret
    Outsider::Teams::Secret.decrypt('google_client_secret', client_secret_encrypted)
  end

  def client_secret=(value)
    self.client_secret_encrypted = Outsider::Teams::Secret.encrypt('google_client_secret', value) if value.present?
  end
end
