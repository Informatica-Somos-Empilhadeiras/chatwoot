# OUTSIDER: liga uma ligação a um negócio do CRM (Entrega 26): ao discar pelo negócio (o telefone manda o negócio
# junto e a central repassa), durante a conversa pelo telefone ou depois, em Telefonia > Ligações. Só vale um
# negócio que a pessoa enxerga no CRM. Ligação que já terminou passa para a linha do tempo do negócio novo e sai
# da do anterior; a que está em andamento entra na do negócio quando acabar (Outsider::Voice::CallEvents).
class Outsider::Voice::DealLink
  def initialize(account_user)
    @account_user = account_user
    @access = Outsider::Crm::Access.new(account_user)
  end

  # o negócio, se a pessoa pode vê-lo
  def deal(id)
    return if id.blank? || !id.to_s.match?(/\A\d+\z/) || !@access.enabled?

    deal = Outsider::Crm::Opportunity.find_by(account_id: @account_user.account_id, id: id)
    deal if deal && @access.view_opportunity?(deal)
  end

  # deal nil desvincula
  def link(call, deal)
    return call if call.opportunity_id == deal&.id

    Outsider::Voice::Call.transaction do
      previous = call.opportunity
      call.update!(opportunity: deal, contact: call.contact || deal&.contact)
      if call.ended_at && !call.internal?
        previous&.activities&.where(kind: :call)&.where("metadata->>'call_id' = ?", call.id.to_s)&.destroy_all
        Outsider::Voice::CallEvents.new(Outsider::Voice::Settings.new(call.account)).log_on_deal(call)
      end
    end
    Outsider::Crm::LiveUpdates.broadcast(call.account_id, 'call', id: call.id, user_id: call.user_id, contact_id: call.contact_id)
    call
  end
end
