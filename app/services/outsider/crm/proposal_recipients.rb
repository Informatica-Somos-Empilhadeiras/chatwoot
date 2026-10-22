# OUTSIDER: para quem e por onde a proposta pode ser enviada. A lista começa pelo contato da proposta e
# pelos contatos da mesma empresa (cadastro de empresas do Chatwoot); a busca acha qualquer outro contato
# da conta. Contato sem telefone ou sem e-mail aparece, mas travado, com o motivo. Grupos do WhatsApp
# ficam de fora. As caixas são as de WhatsApp (oficial, Twilio ou Evolution) e de e-mail que a pessoa
# atende (administrador: todas). Sem caixa de e-mail, o e-mail sai pelo servidor de e-mail do Chatwoot.
class Outsider::Crm::ProposalRecipients
  LIMIT = 20

  def initialize(account_user, proposal)
    @account_user = account_user
    @account = account_user.account
    @proposal = proposal
  end

  def contacts(query = nil)
    list = query.present? ? search(query) : suggested
    list.reject { |contact| Outsider::Crm::ContactSummary.group?(contact) }.first(LIMIT).map { |contact| contact_row(contact) }
  end

  def whatsapp_inboxes
    @whatsapp_inboxes ||= inboxes.select { |inbox| whatsapp?(inbox) }
  end

  def email_inboxes
    @email_inboxes ||= inboxes.select(&:email?)
  end

  def system_email?
    ENV['SMTP_ADDRESS'].present? || Rails.env.development?
  end

  def whatsapp?(inbox)
    inbox.whatsapp? || (inbox.twilio? && inbox.channel.medium == 'whatsapp') || Outsider::EvolutionApi.evolution_inbox?(inbox)
  end

  def inbox_row(inbox)
    { id: inbox.id, name: inbox.name, channel_type: inbox.channel_type }
  end

  private

  def inboxes
    @inboxes ||= begin
      scope = @account_user.administrator? ? @account.inboxes : @account_user.user.inboxes.where(account_id: @account.id)
      scope.includes(:channel).order(:name).to_a
    end
  end

  def suggested
    contact = @proposal.contact
    colleagues = contact.company_id ? @account.contacts.where(company_id: contact.company_id).where.not(id: contact.id).order(:name).limit(LIMIT) : []
    [contact, *colleagues]
  end

  def search(query)
    term = "%#{Contact.sanitize_sql_like(query.to_s.strip)}%"
    @account.contacts.where('name ILIKE :term OR email ILIKE :term OR phone_number ILIKE :term', term: term).order(:name).limit(LIMIT + 5).to_a
  end

  def contact_row(contact)
    Outsider::Crm::Serializer.contact(contact).merge(
      company_name: company_name(contact), default_inbox_id: last_whatsapp_inbox_id(contact),
      blocked: { whatsapp: contact.phone_number.blank? ? 'no_phone' : nil, email: contact.email.blank? ? 'no_email' : nil }
    )
  end

  # Empresa do contato: o cadastro de empresas (Enterprise) ou o campo "empresa" do contato
  def company_name(contact)
    contact.try(:company)&.name.presence || contact.additional_attributes.to_h['company_name']
  end

  # Caixa da conversa mais recente com o contato, entre as de WhatsApp que a pessoa atende
  def last_whatsapp_inbox_id(contact)
    ids = whatsapp_inboxes.map(&:id)
    return if ids.empty?

    @account.conversations.where(contact_id: contact.id, inbox_id: ids).order(last_activity_at: :desc).pick(:inbox_id)
  end
end
