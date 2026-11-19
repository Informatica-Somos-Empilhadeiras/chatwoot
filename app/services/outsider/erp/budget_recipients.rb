# OUTSIDER: para quem e por onde o orçamento pode ir. WhatsApp: as caixas de WhatsApp que a pessoa atende (a regra é a
# mesma das propostas do CRM, Outsider::Crm::ProposalRecipients) e o contato do orçamento, ou outro achado pela busca.
# E-mail: já sugere o e-mail do contato e os do cliente no ERP.
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
    contact = budget.contact
    {
      contact: contact && Outsider::Crm::Serializer.contact(contact), inboxes: whatsapp_inboxes.map { |inbox| crm.inbox_row(inbox) },
      inbox_id: default_inbox_id(budget, contact), emails: emails(contact, report), mail_server: system_email?
    }
  end

  private

  def crm
    @crm ||= Outsider::Crm::ProposalRecipients.new(@account_user, nil)
  end

  # a caixa da conversa em que o orçamento foi feito, senão a da conversa mais recente com o contato
  def default_inbox_id(budget, contact)
    ids = whatsapp_inboxes.map(&:id)
    from_conversation = budget.conversation_id && @account.conversations.where(id: budget.conversation_id, inbox_id: ids).pick(:inbox_id)
    from_conversation || (contact && @account.conversations.where(contact_id: contact.id,
                                                                  inbox_id: ids).order(last_activity_at: :desc).pick(:inbox_id))
  end

  def emails(contact, report)
    ([contact&.email] + Outsider::Erp::CustomerRecord.emails(report['cliente'].to_h)).compact_blank.uniq(&:downcase)
  end
end
