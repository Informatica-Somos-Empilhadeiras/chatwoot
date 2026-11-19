# OUTSIDER: busca de novo as OS ou os orçamentos do ERP quando a cópia passou do tempo (Outsider::Erp::Snapshot), fora da
# requisição da tela. Uma por vez por conta (trava no Redis); se o ERP falhar, fica valendo a cópia anterior.
class Outsider::Erp::RefreshJob < ApplicationJob
  queue_as :low

  def perform(account_id, name)
    account = Account.find_by(id: account_id)
    return unless account && Outsider::Erp::Settings.new(account).enabled?

    source = name == 'quotes' ? Outsider::Erp::Quotes.new(account) : Outsider::Erp::ServiceOrders.new(account)
    source.snapshot.refresh!
  rescue Outsider::Erp::Client::Error => e
    Rails.logger.warn("[Outsider::Erp] conta #{account_id} #{name}: #{e.message}")
  end
end
