# OUTSIDER: busca de conversas por nome ou telefone do contato, numa consulta só.
#
# - nome: cada palavra precisa aparecer, sem diferenciar acento nem maiúscula; cada palavra vira uma
#   expressão regular que o índice trigram de contacts.name consegue usar (Outsider::TextPattern)
# - telefone: a partir de 4 dígitos, em qualquer formato ("(11) 9999-0000", "+55 11...")
# - uma conversa por contato e caixa: a que não está resolvida, ou a mais recente
# - agentes recebem também as conversas de outros agentes, marcadas como bloqueadas
#   (ver locked?), para saber com quem está o contato
# - contatos que batem e não estão nessas conversas (sem conversa ou só em caixas que o agente não vê)
class Outsider::ConversationSearch
  LIMIT = 30
  CONTACTS_LIMIT = 8
  MIN_PHONE_DIGITS = 4
  MIN_EMAIL_LENGTH = 3
  # DISTINCT ON fica com a primeira de cada contato e caixa: não resolvida antes, depois a mais recente
  LATEST_ORDER = "conversations.contact_id, conversations.inbox_id, (conversations.status = #{Conversation.statuses[:resolved]}), " \
                 'conversations.last_activity_at DESC'.freeze

  def initialize(account, user, query)
    @account = account
    @user = user
    @query = query.to_s.strip
  end

  def perform
    return Conversation.none if @query.length < 2

    @account.conversations.where(id: latest_per_contact_and_inbox)
            .includes(:contact, :inbox, :assignee, :team)
            .order(last_activity_at: :desc).limit(LIMIT)
  end

  def locked?(conversation)
    !administrator? && conversation.assignee_id.present? && conversation.assignee_id != @user.id
  end

  # contatos que batem com a busca e não aparecem nas conversas encontradas, os mais recentes primeiro
  def contacts(conversations)
    return Contact.none if @query.length < 2

    matching_contacts.where.not(id: conversations.map(&:contact_id))
                     .reorder(Arel.sql('contacts.last_activity_at DESC NULLS LAST, contacts.id DESC'))
                     .limit(CONTACTS_LIMIT)
  end

  # pedidos de transferência que esta pessoa fez e ainda esperam resposta, por conversa
  def pending_transfers(conversations)
    ids = conversations.select { |conversation| locked?(conversation) }.map(&:id)
    return {} if ids.empty?

    ::Outsider::TransferRequest.where(account_id: @account.id, requester_id: @user.id, conversation_id: ids)
                               .pending.index_by(&:conversation_id)
  end

  private

  def latest_per_contact_and_inbox
    scope = @account.conversations.where(contact_id: matching_contacts.select(:id))
    Conversations::PermissionFilterService.new(scope, @user, @account).perform
                                          .select('DISTINCT ON (conversations.contact_id, conversations.inbox_id) conversations.id')
                                          .reorder(Arel.sql(LATEST_ORDER))
  end

  def matching_contacts
    words = ::Outsider::TextPattern.terms(@query, min_length: 1)
    by_name = words.inject(@account.contacts) { |scope, word| scope.where('contacts.name ~* ?', ::Outsider::TextPattern.pattern_for(word)) }
    by_name = by_name.or(by_email) if @query.length >= MIN_EMAIL_LENGTH && @query.exclude?(' ')
    digits = @query.delete('^0-9')
    return by_name if digits.length < MIN_PHONE_DIGITS

    by_name.or(@account.contacts.where('contacts.phone_number LIKE :digits OR contacts.identifier LIKE :digits', digits: "%#{digits}%"))
  end

  def by_email
    @account.contacts.where('contacts.email ILIKE ?', "%#{Contact.sanitize_sql_like(@query)}%")
  end

  def administrator?
    @administrator ||= @account.account_users.find_by(user: @user)&.administrator?
  end
end
