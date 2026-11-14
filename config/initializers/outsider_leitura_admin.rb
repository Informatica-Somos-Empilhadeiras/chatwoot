# OUTSIDER: administrador não marca como lida a conversa de outro agente (ver app/services/outsider/leitura_admin.rb)
Rails.application.config.to_prepare do
  controller = Api::V1::Accounts::ConversationsController
  controller.prepend(Outsider::LeituraAdmin) unless controller < Outsider::LeituraAdmin
end
