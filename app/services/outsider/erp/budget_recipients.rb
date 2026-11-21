# OUTSIDER: para quem e por onde o orçamento (e o relatório da OS) pode ir. WhatsApp: as caixas de WhatsApp que a pessoa
# atende (a regra é a mesma das propostas do CRM, Outsider::Crm::ProposalRecipients) e o contato, ou outro achado pela
# busca. E-mail: já sugere o e-mail do contato e, no orçamento, os do cliente no ERP.
class Outsider::Erp::BudgetRecipients
  delegate :whatsapp_inboxes, :system_email?, to: :crm

  def initialize(account_user)
    @account_user = account_user
    @account = account_user.account
  end

  # busca de outro contato (a lista começa vazia: o contato do orçamento já vem nos padrões)
  def contacts(query)
    query.to_s.strip.empty? ? [] : crm.contacts(query)
  end

  def defaults(budget, report)
    for_contact(budget.contact, conversation_id: budget.conversation_id, emails: Outsider::Erp::CustomerRecord.emails(report['cliente'].to_h))
  end

  # o contato, a caixa (a da conversa de onde o envio saiu, senão a da conversa mais recente com ele) e os e-mails
  # sugeridos, o do contato primeiro
  def for_contact(contact, conversation_id: nil, emails: [])
    {
      contact: contact && Outsider::Crm::Serializer.contact(contact), inboxes: whatsapp_inboxes.map { |inbox| crm.inbox_row(inbox) },
      inbox_id: default_inbox_id(conversation_id, contact), emails: ([contact&.email] + emails).compact_blank.uniq(&:downcase),
      mail_server: system_email?
    }
  end

  private

  def crm
    @crm ||= Outsider::Crm::ProposalRecipients.new(@account_user, nil)
  end

  def default_inbox_id(conversation_id, contact)
    ids = whatsapp_inboxes.map(&:id)
    from_conversation = conversation_id && @account.conversations.where(id: conversation_id, inbox_id: ids).pick(:inbox_id)
    from_conversation || (contact && @account.conversations.where(contact_id: contact.id,
                                                                  inbox_id: ids).order(last_activity_at: :desc).pick(:inbox_id))
  end
end
