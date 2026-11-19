# OUTSIDER: o que a tela de quem está logado pode fazer com o ERP (o painel some com a integração desligada)
class Api::V1::Accounts::Outsider::Erp::StatusesController < Api::V1::Accounts::Outsider::Erp::BaseController
  skip_before_action :ensure_erp_enabled

  def show
    render json: {
      enabled: settings.enabled?, can_edit: settings.enabled? && can_edit?, write_enabled: settings.write_enabled?,
      quotes_enabled: settings.quotes_enabled?, administrator: Current.account_user.administrator?,
      fields: settings.writable_fields.keys, field_kinds: ::Outsider::Erp::Settings::FIELD_KINDS, companies: settings.companies,
      quote_write_enabled: settings.quote_write_enabled?, can_create_quote: settings.enabled? && can_create_quote?
    }
  end
end
