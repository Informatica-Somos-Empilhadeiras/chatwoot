# OUTSIDER: CRM visto a partir de um contato do Chatwoot. show alimenta a aba CRM da conversa e o
# bloco do painel do contato; summaries devolve, de uma vez, o valor em aberto de vários contatos
# para o selo nos cards da lista de conversas; history é o histórico multiempresa do contato.
class Api::V1::Accounts::Outsider::Crm::ContactsController < Api::V1::Accounts::Outsider::Crm::BaseController
  SUMMARIES_LIMIT = 100

  def show
    contact = Current.account.contacts.find(params[:id])
    render json: ::Outsider::Crm::ContactSummary.new(contact, access: crm_access, conversation_display_id: params[:conversation_id]).to_h
  end

  def history
    contact = Current.account.contacts.find(params[:id])
    render json: ::Outsider::Crm::ContactHistory.new(contact, access: crm_access).to_h
  end

  def summaries
    ids = params[:ids].to_s.split(',').map(&:to_i).select(&:positive?).uniq.first(SUMMARIES_LIMIT)
    rows = crm_access.opportunities(crm_scope(::Outsider::Crm::Opportunity)).open.where(contact_id: ids)
                     .group(:contact_id).pluck(:contact_id, Arel.sql('COUNT(*)'), Arel.sql('SUM(value_cents)'))
    render json: rows.to_h { |contact_id, count, total| [contact_id, { open_count: count, open_value_cents: total.to_i }] }
  end
end
