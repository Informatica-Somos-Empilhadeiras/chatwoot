# OUTSIDER: busca de conversas por nome ou telefone do contato, numa consulta só.
#
# - nome: cada palavra precisa aparecer, sem diferenciar acento nem maiúscula
# - telefone: a partir de 4 dígitos, em qualquer formato ("(11) 9999-0000", "+55 11...")
# - uma conversa por contato e caixa: a que não está resolvida, ou a mais recente
# - agentes recebem também as conversas de outros agentes, marcadas como bloqueadas
#   (ver locked?), para saber com quem está o contato
class Outsider::ConversationSearch
  LIMIT = 30
  MIN_PHONE_DIGITS = 4
  ACCENTS = 'áàâãäéèêëíìîïóòôõöúùûüçñ'.freeze
  PLAIN = 'aaaaaeeeeiiiiooooouuuucn'.freeze
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

  private

  def latest_per_contact_and_inbox
    scope = @account.conversations.where(contact_id: matching_contacts.select(:id))
    Conversations::PermissionFilterService.new(scope, @user, @account).perform
                                          .select('DISTINCT ON (conversations.contact_id, conversations.inbox_id) conversations.id')
                                          .reorder(Arel.sql(LATEST_ORDER))
  end

  def matching_contacts
    words = normalize(@query).split.map { |word| "%#{ActiveRecord::Base.sanitize_sql_like(word)}%" }
    by_name = words.inject(@account.contacts) { |scope, word| scope.where("translate(lower(contacts.name), '#{ACCENTS}', '#{PLAIN}') LIKE ?", word) }
    digits = @query.delete('^0-9')
    return by_name if digits.length < MIN_PHONE_DIGITS

    by_name.or(@account.contacts.where('contacts.phone_number LIKE :digits OR contacts.identifier LIKE :digits', digits: "%#{digits}%"))
  end

  def normalize(text)
    text.downcase.tr(ACCENTS, PLAIN)
  end

  def administrator?
    @administrator ||= @account.account_users.find_by(user: @user)&.administrator?
  end
end
