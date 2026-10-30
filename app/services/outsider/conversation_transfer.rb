# OUTSIDER: pedido de transferência de conversa entre agentes.
#
# Quem pede (requester) achou na busca uma conversa que está com outro agente (holder). O holder recebe
# um aviso que fica na tela até ele aceitar ou recusar. Aceitou: a conversa passa para quem pediu (a
# atividade "atribuída por" fica no nome de quem aceitou) e quem pediu vê um aviso rápido. Recusou: quem
# pediu vê o aviso até clicar em OK. Os avisos chegam pelo canal do próprio usuário no Chatwoot
# (evento 'outsider.notice'); a tela também busca a lista ao abrir, então nada se perde se a pessoa
# estiver fora.
class Outsider::ConversationTransfer
  EVENT = 'outsider.notice'.freeze

  class Error < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code.to_s)
    end
  end

  def initialize(account, user)
    @account = account
    @user = user
  end

  # pedidos que ainda importam para esta pessoa: os que esperam resposta dela, os dela esperando
  # resposta e as respostas que ela ainda não viu. Pedidos de conversas que mudaram de agente por
  # outro caminho expiram aqui.
  def overview
    expire_stale(requests.pending.where(holder_id: @user.id).or(requests.pending.where(requester_id: @user.id)))
    {
      incoming: requests.pending.where(holder_id: @user.id).order(:created_at).to_a,
      outgoing: requests.pending.where(requester_id: @user.id).order(:created_at).to_a,
      answered: requests.where(requester_id: @user.id, status: %i[accepted declined]).unacknowledged
                        .where('outsider_transfer_requests.decided_at > ?', 7.days.ago).order(:decided_at).to_a
    }
  end

  def request(conversation, note = nil)
    raise Error, :not_found unless visible?(conversation)
    raise Error, :not_assigned_to_other if conversation.assignee_id.blank? || conversation.assignee_id == @user.id

    existing = requests.pending.find_by(conversation_id: conversation.id, requester_id: @user.id)
    return existing if existing&.current?

    existing&.update!(status: :expired, decided_at: Time.current)
    transfer = requests.create!(conversation: conversation, requester: @user, holder_id: conversation.assignee_id,
                                note: note.to_s.strip.first(500).presence)
    notify(transfer.holder, 'created', transfer)
    transfer
  end

  def accept(transfer)
    answerable!(transfer)
    conversation = transfer.conversation
    ActiveRecord::Base.transaction do
      Conversations::AssignmentService.new(conversation: conversation, assignee_id: transfer.requester_id).perform
      transfer.update!(status: :accepted, decided_at: Time.current)
      others = requests.pending.where(conversation_id: conversation.id).where.not(id: transfer.id).to_a
      others.each { |other| other.update!(status: :expired, decided_at: Time.current) }
      @expired = others
    end
    notify(transfer.requester, 'accepted', transfer)
    @expired.each { |other| notify(other.requester, 'expired', other) }
    transfer
  end

  def decline(transfer, note = nil)
    answerable!(transfer)
    transfer.update!(status: :declined, decided_at: Time.current, note: note.to_s.strip.first(500).presence || transfer.note)
    notify(transfer.requester, 'declined', transfer)
    transfer
  end

  # quem pediu clicou em OK (recusado) ou viu o aviso de que recebeu a conversa
  def acknowledge(transfer)
    raise Error, :not_found unless transfer.requester_id == @user.id

    transfer.update!(acknowledged_at: Time.current) if transfer.acknowledged_at.blank?
    notify(@user, 'acknowledged', transfer)
    transfer
  end

  def cancel(transfer)
    raise Error, :not_found unless transfer.requester_id == @user.id
    raise Error, :already_answered unless transfer.pending?

    transfer.update!(status: :cancelled, decided_at: Time.current)
    notify(transfer.holder, 'cancelled', transfer)
    notify(@user, 'cancelled', transfer)
    transfer
  end

  def requests
    ::Outsider::TransferRequest.where(account_id: @account.id).includes(:requester, :holder, conversation: :contact)
  end

  def self.serialize(transfer)
    conversation = transfer.conversation
    contact = conversation&.contact
    {
      id: transfer.id,
      status: transfer.status,
      note: transfer.note,
      created_at: transfer.created_at.to_i,
      decided_at: transfer.decided_at&.to_i,
      conversation: conversation && { id: conversation.display_id, inbox_id: conversation.inbox_id },
      contact: contact && { id: contact.id, name: contact.name, phone_number: contact.phone_number, thumbnail: contact.avatar_url },
      requester: person(transfer.requester),
      holder: person(transfer.holder)
    }
  end

  def self.person(user)
    user && { id: user.id, name: user.available_name, thumbnail: user.avatar_url }
  end

  private

  def answerable!(transfer)
    raise Error, :not_found unless transfer.holder_id == @user.id
    raise Error, :already_answered unless transfer.pending?
    return if transfer.current?

    transfer.update!(status: :expired, decided_at: Time.current)
    notify(transfer.requester, 'expired', transfer)
    raise Error, :conversation_changed
  end

  def expire_stale(scope)
    scope.to_a.reject(&:current?).each do |transfer|
      transfer.update!(status: :expired, decided_at: Time.current)
      notify(transfer.requester, 'expired', transfer) if transfer.requester_id != @user.id
    end
  end

  def visible?(conversation)
    conversation.account_id == @account.id &&
      Conversations::PermissionFilterService.new(@account.conversations, @user, @account).perform.exists?(id: conversation.id)
  end

  def notify(user, action, transfer)
    return if user&.pubsub_token.blank?

    data = { account_id: @account.id, kind: 'transfer_request', action: action, request: self.class.serialize(transfer) }
    ActionCable.server.broadcast(user.pubsub_token, { event: EVENT, data: data })
  end
end
