# OUTSIDER: o que o usuário atual pode fazer no CRM; o frontend usa para montar menu e telas. Sem
# acesso (CRM desligado na conta ou para a pessoa, ou fora das unidades), vem só enabled false e o motivo.
class Api::V1::Accounts::Outsider::Crm::AccessesController < Api::V1::Accounts::Outsider::Crm::BaseController
  skip_before_action :ensure_crm_access

  def show
    return render json: crm_access.as_json unless crm_access.enabled?

    render json: crm_access.as_json.merge(settings: ::Outsider::Crm::Settings.new(Current.account).to_h,
                                          disabled_user_ids: ::Outsider::Crm::Switch.new(Current.account).disabled_agent_ids)
  end
end
