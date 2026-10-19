# OUTSIDER: o que o usuário atual pode fazer no CRM; o frontend usa para montar menu e telas.
class Api::V1::Accounts::Outsider::Crm::AccessesController < Api::V1::Accounts::Outsider::Crm::BaseController
  skip_before_action :ensure_crm_access

  def show
    render json: crm_access.as_json.merge(settings: ::Outsider::Crm::Settings.new(Current.account).to_h)
  end
end
