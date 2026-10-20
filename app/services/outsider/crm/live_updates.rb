# OUTSIDER: avisa as telas do CRM abertas na conta que algo mudou (negócio, tarefa, metas ou
# configurações), para elas recarregarem na hora. Vai só o tipo e os ids: cada tela busca de novo
# pela API, que aplica as permissões de quem está vendo. Canal: Outsider::Crm::UpdatesChannel.
module Outsider::Crm::LiveUpdates
  def self.stream(account_id)
    "outsider_crm_#{account_id}"
  end

  def self.broadcast(account_id, kind, data = {})
    ActionCable.server.broadcast(stream(account_id), data.merge(kind: kind))
  rescue StandardError => e
    # sem aviso ao vivo as telas continuam certas ao recarregar; não derruba a gravação
    Rails.logger.warn("[outsider_crm] live update failed: #{e.message}")
  end

  def self.record_changed(record)
    case record
    when Outsider::Crm::Opportunity
      broadcast(record.account_id, 'opportunity', id: record.id, business_unit_id: record.business_unit_id,
                                                  contact_id: record.contact_id, owner_id: record.owner_id)
    when Outsider::Crm::Task
      broadcast(record.account_id, 'task', id: record.id, opportunity_id: record.opportunity_id, assignee_id: record.assignee_id,
                                           contact_id: record.opportunity&.contact_id)
    end
  end
end
