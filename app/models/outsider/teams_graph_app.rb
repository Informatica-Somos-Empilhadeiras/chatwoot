# OUTSIDER: o aplicativo da empresa no Microsoft Entra ID para o "Conectar meu Teams" (um por conta). O TI registra uma
# vez (ID do aplicativo, ID do locatário e um segredo) e dá o consentimento de administrador; depois cada colaborador só
# entra com a conta Microsoft dele (Outsider::Teams::Graph::Login).
class Outsider::TeamsGraphApp < ApplicationRecord
  self.table_name = 'outsider_teams_graph_apps'

  GUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  belongs_to :account

  validates :client_id, :tenant_id, format: { with: GUID }
  validates :client_secret_encrypted, presence: true
  validates :account_id, uniqueness: true

  def client_secret
    Outsider::Teams::Secret.decrypt('graph_client_secret', client_secret_encrypted)
  end

  def client_secret=(value)
    self.client_secret_encrypted = Outsider::Teams::Secret.encrypt('graph_client_secret', value) if value.present?
  end
end
