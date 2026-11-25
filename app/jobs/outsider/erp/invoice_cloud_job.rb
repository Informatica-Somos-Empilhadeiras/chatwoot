# OUTSIDER: aviso das notas fiscais que ainda não foram para a nuvem (Outsider::Erp::InvoiceCloud). Sem argumentos: o passe
# periódico (cron a cada 30 minutos) de todas as contas com o ERP e o Nextcloud ligados. Com conta e nota: a segunda
# busca de uma nota que estava na nuvem e falhou ao abrir.
class Outsider::Erp::InvoiceCloudJob < ApplicationJob
  queue_as :low

  LOCK = 'outsider:erp:nf_nuvem:passe'.freeze

  def perform(account_id = nil, key = nil)
    if account_id && key
      target = Account.find_by(id: account_id)
      Outsider::Erp::InvoiceCloud.new(target).recheck(key) if target
      return
    end
    return unless Redis::Alfred.set(LOCK, 1, nx: true, ex: 25.minutes.to_i)

    begin
      accounts.each { |account| Outsider::Erp::InvoiceCloud.new(account).sweep }
    ensure
      Redis::Alfred.delete(LOCK)
    end
  end

  private

  # só as contas com o ERP configurado (as configurações moram em accounts.internal_attributes)
  def accounts
    Account.where("internal_attributes ->> 'outsider_erp' IS NOT NULL").find_each.select do |account|
      Outsider::Erp::InvoiceCloud.new(account).enabled?
    end
  end
end
