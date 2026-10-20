# OUTSIDER: "Verificar agora" da automação de negócio parado e das regras com gatilho de tempo, para o
# administrador não depender do agendamento de hora em hora (e para testar no ambiente de
# desenvolvimento, que não roda o Sidekiq).
class Api::V1::Accounts::Outsider::Crm::AutomationsController < Api::V1::Accounts::Outsider::Crm::BaseController
  before_action :ensure_crm_admin

  def stalled
    render json: {
      created: ::Outsider::Crm::StalledOpportunities.new(Current.account).perform,
      rules: ::Outsider::Crm::TimedRules.new(Current.account).perform
    }
  end
end
