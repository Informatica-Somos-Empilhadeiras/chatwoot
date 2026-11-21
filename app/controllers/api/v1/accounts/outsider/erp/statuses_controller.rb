# OUTSIDER: o que a tela de quem está logado pode fazer com o ERP (o painel some com a integração desligada)
class Api::V1::Accounts::Outsider::Erp::StatusesController < Api::V1::Accounts::Outsider::Erp::BaseController
  skip_before_action :ensure_erp_enabled

  def show
    render json: {
      enabled: settings.enabled?, can_edit: settings.enabled? && can_edit?, write_enabled: settings.write_enabled?,
      orders_enabled: settings.orders_enabled?, quotes_enabled: settings.quotes_enabled?, administrator: Current.account_user.administrator?,
      fields: settings.writable_fields.keys, field_kinds: ::Outsider::Erp::Settings::FIELD_KINDS, companies: settings.companies,
      locked_statuses: settings.locked_statuses
    }.merge(writes)
  end

  private

  # gravações com flag própria: orçamento e cadastro de cliente (Outsider::Erp::ClientRegistrar)
  def writes
    {
      quote_write_enabled: settings.quote_write_enabled?, can_create_quote: settings.enabled? && can_create_quote?,
      client_write_enabled: settings.client_write_enabled?, can_register_client: can_register_client?
    }
  end
end
