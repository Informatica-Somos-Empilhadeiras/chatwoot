# OUTSIDER: busca de mensagens na conta toda, como a do WhatsApp.
#
# Cada palavra vira uma expressão regular sem acento nem maiúscula (Outsider::TextPattern) e o
# Postgres usa o índice trigram de messages.content: o custo depende de quantas mensagens têm a
# palavra, não do tamanho da tabela. Por isso pelo menos uma palavra precisa ter 3 letras.
# "messages.id + 0" impede o Postgres de varrer o índice da chave da tabela toda (todas as
# contas) atrás das poucas linhas que batem.
#
# Agentes só veem mensagens das conversas das caixas deles que estão sem agente ou com eles:
# as de outros agentes aparecem na busca de conversas, bloqueadas, sem mensagem nenhuma.
class Outsider::MessageSearch
  PER_PAGE = 20
  EXCERPT_LENGTH = 160
  TIMEOUT_MS = 8000
  DELETED_PATTERN = ::Outsider::ConversationHistory::DELETED_PATTERN
  GROUP_HEADER = ::Outsider::ConversationHistory::GROUP_HEADER

  def initialize(account, user, query, before_id: nil)
    @account = account
    @user = user
    @terms = ::Outsider::TextPattern.terms(query, min_length: 2)
    @before_id = before_id.presence&.to_i
  end

  def perform
    return { payload: [], has_more: false, too_short: true } unless ::Outsider::TextPattern.indexable?(@terms)

    page = with_timeout { matching.limit(PER_PAGE + 1).to_a }
    return { payload: [], has_more: false, timeout: true } if page.nil?

    {
      payload: page.first(PER_PAGE).map { |message| serialize(message) },
      has_more: page.size > PER_PAGE
    }
  end

  private

  def matching
    scope = Message.where(account_id: @account.id).where.not(message_type: :activity)
                   .where.not(content: [nil, ''])
                   .where("COALESCE(messages.content_attributes::text, '') !~ ?", DELETED_PATTERN)
    @terms.each { |term| scope = scope.where('messages.content ~* ?', ::Outsider::TextPattern.pattern_for(term)) }
    scope = scope.where('messages.id < ?', @before_id) if @before_id
    scope = scope.where(conversation_id: visible_conversations.select(:id)) unless administrator?
    scope.reorder(Arel.sql('messages.id + 0 DESC'))
         .includes(:sender, :attachments, conversation: [:contact, :assignee])
  end

  def visible_conversations
    Conversations::PermissionFilterService.new(@account.conversations, @user, @account).perform
                                          .where('conversations.assignee_id IS NULL OR conversations.assignee_id = ?', @user.id)
  end

  # uma palavra muito comum numa conta enorme não pode travar o servidor
  def with_timeout
    Message.transaction do
      Message.connection.execute("SET LOCAL statement_timeout = #{TIMEOUT_MS}")
      yield
    end
  rescue ActiveRecord::QueryCanceled
    nil
  end

  def serialize(message)
    conversation = message.conversation
    contact = conversation.contact
    {
      id: message.id,
      created_at: message.created_at.to_i,
      message_type: message.message_type_before_type_cast,
      private: message.private,
      content: excerpt(message.content.to_s),
      sender_name: message.sender.try(:available_name) || message.sender.try(:name),
      attachment_type: message.attachments.first&.file_type,
      conversation: {
        id: conversation.display_id,
        inbox_id: conversation.inbox_id,
        status: conversation.status,
        assignee_name: conversation.assignee&.available_name
      },
      contact: { id: contact&.id, name: contact&.name, thumbnail: contact&.avatar_url }
    }
  end

  # o pedaço da mensagem onde a primeira palavra aparece, sem o "**Nome:**" dos grupos
  def excerpt(text)
    text = text.sub(GROUP_HEADER, '').squish
    return text if text.length <= EXCERPT_LENGTH

    first = @terms.filter_map { |term| ::Outsider::TextPattern.normalize(text).index(term) }.min.to_i
    start = [first - (EXCERPT_LENGTH / 4), 0].max
    piece = text[start, EXCERPT_LENGTH]
    "#{'…' if start.positive?}#{piece}#{'…' if start + EXCERPT_LENGTH < text.length}"
  end

  def administrator?
    @administrator ||= @account.account_users.find_by(user: @user)&.administrator?
  end
end
