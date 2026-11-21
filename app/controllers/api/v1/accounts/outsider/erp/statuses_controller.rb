# OUTSIDER: o que a tela de quem está logado pode fazer com o ERP (o painel some com a integração desligada)
class Api::V1::Accounts::Outsider::Erp::StatusesController < Api::V1::Accounts::Outsider::Erp::BaseController
  skip_before_action :ensure_erp_enabled

  def show
    render json: {
      enabled: settings.enabled?, can_edit: settings.enabled? && can_edit?, write_enabled: settings.write_enabled?,
      orders_enabled: settings.orders_enabled?, quotes_enabled: settings.quotes_enabled?, administrator: Current.account_user.administrator?,
      fields: settings.writable_fields.keys, field_kinds: ::Outsider::Erp::Settings::FIELD_KINDS,
      locked_statuses: settings.locked_statuses
    }.merge(writes, nextcloud, units)
  end

  private

  # as unidades (bancos do ERP) e o nome de cada uma nas telas
  def units
    { companies: settings.companies, company_names: settings.company_names }
  end

  # o que vem do Nextcloud: as notas fiscais em PDF e as fotos dos produtos
  def nextcloud
    { nextcloud_invoices: settings.nextcloud_enabled?, product_photos: settings.product_photos_enabled? }
  end

  # gravações com flag própria: orçamento e cadastro de cliente (Outsider::Erp::ClientRegistrar)
  def writes
    {
      quote_write_enabled: settings.quote_write_enabled?, can_create_quote: settings.enabled? && can_create_quote?,
      client_write_enabled: settings.client_write_enabled?, can_register_client: can_register_client?
    }
  end
end
