# OUTSIDER: busca de novo uma cópia do ERP (as OS, os orçamentos ou a lista de clientes; Outsider::Erp::Snapshot) quando
# ela passou do tempo, fora da requisição da tela. Uma por vez por conta (trava no Redis); se o ERP falhar, fica valendo
# a cópia anterior. Cópia nova = uma linha a mais em SOURCES.
class Outsider::Erp::RefreshJob < ApplicationJob
  queue_as :low

  SOURCES = { 'os' => 'Outsider::Erp::ServiceOrders', 'quotes' => 'Outsider::Erp::Quotes', 'customers' => 'Outsider::Erp::Customers' }.freeze

  def perform(account_id, name)
    account = Account.find_by(id: account_id)
    source = SOURCES[name]
    return unless source && account && Outsider::Erp::Settings.new(account).enabled?

    source.constantize.new(account).snapshot.refresh!
  rescue Outsider::Erp::Client::Error => e
    Rails.logger.warn("[Outsider::Erp] conta #{account_id} #{name}: #{e.message}")
  end
end
