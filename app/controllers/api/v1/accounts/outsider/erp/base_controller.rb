# OUTSIDER: base da API da integração com o ERP (ver app/services/outsider/erp/settings.rb). Sessão, conta e papel vêm do
# Chatwoot; o perfil de acesso (tela "erp") já barrou quem não vê e, para quem só vê, o que grava (Outsider::Access::ApiGuard).
class Api::V1::Accounts::Outsider::Erp::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_erp_enabled

  rescue_from(::Outsider::Erp::Snapshot::Loading) { render json: { error: 'loading' }, status: :accepted }
  rescue_from(::Outsider::Erp::Client::Error) do |error|
    render json: { error: 'erp_unavailable', message: error.message }, status: :service_unavailable
  end

  private

  def settings
    @settings ||= ::Outsider::Erp::Settings.new(Current.account)
  end

  def orders
    @orders ||= ::Outsider::Erp::ServiceOrders.new(Current.account)
  end

  def ensure_erp_enabled
    render json: { error: 'erp_disabled' }, status: :forbidden unless settings.enabled?
  end

  # quadro e busca de OS: somem com "Mostrar ordens de serviço" desligado (ficam só os orçamentos)
  def ensure_orders_enabled
    render json: { error: 'orders_disabled' }, status: :forbidden unless settings.orders_enabled?
  end

  def ensure_erp_admin
    render json: { error: 'erp_admin_only' }, status: :forbidden unless Current.account_user.administrator?
  end

  def contact
    @contact ||= Current.account.contacts.find(params.require(:contact_id))
  end

  def can_edit?
    settings.write_enabled? && can_use_erp?
  end

  # acesso de uso da integração (ver/editar), sem exigir a flag de escrita — para buscas de apoio (produtos, listas)
  def can_use_erp?
    ::Outsider::Access.for(Current.account_user).allows?('erp', 'use')
  end

  # criar orçamento no ERP: flag própria (desligada por padrão) + acesso de uso
  def can_create_quote?
    settings.quote_write_enabled? && can_use_erp?
  end
end
