# OUTSIDER: atendimento e fim das ligações, avisados pela central (Entrega 22).
#
# Atendida: guarda quem atendeu e a hora. Fim: duração da conversa e situação final. Recebida que ninguém
# atendeu vira tarefa "Retornar ligação" no negócio aberto do cliente (para o dono). Quando um vendedor liga
# para o número e o cliente atende, as perdidas desse número saem da fila de retorno e a tarefa fica feita.
# As ligações com cliente aparecem na linha do tempo do negócio.
class Outsider::Voice::CallEvents
  # DIALSTATUS do Asterisk quando ninguém conversou
  OUTBOUND_STATUS = { 'BUSY' => :busy, 'CHANUNAVAIL' => :failed, 'CONGESTION' => :failed }.freeze
  RETURN_WINDOW = 7.days

  def initialize(settings)
    @settings = settings
    @account = settings.account
  end

  def answered(linkedid:, endpoint:)
    call = find(linkedid)
    return unless call&.ringing?

    user_id = @settings.user_id_for_extension(endpoint) || call.user_id
    call.update!(status: :answered, answered_at: Time.current, user_id: user_id)
    broadcast(call)
  end

  def hangup(linkedid:, dialstatus:, cause:)
    call = find(linkedid)
    return unless call && call.ended_at.nil?

    now = Time.current
    call.update!(ended_at: now, hangup_cause: cause.presence, status: final_status(call, dialstatus),
                 talk_seconds: call.answered_at ? (now - call.answered_at).round : 0)
    after_end(call)
    broadcast(call)
  end

  private

  def find(linkedid)
    Outsider::Voice::Call.find_by(account_id: @account.id, linkedid: linkedid)
  end

  def final_status(call, dialstatus)
    return :answered if call.answered_at
    return :missed if call.inbound?

    OUTBOUND_STATUS.fetch(dialstatus.to_s, :unanswered)
  end

  def after_end(call)
    return if call.internal?

    create_return_task(call) if call.missed?
    mark_returned(call) if call.outbound? && call.answered?
    log_on_deal(call)
  end

  def create_return_task(call)
    deal = call.opportunity
    return unless deal&.open?

    title = I18n.with_locale(@account.locale) { I18n.t('outsider_voice.return_task', name: call.contact&.name || call.from_number) }
    task = deal.tasks.create!(account_id: @account.id, kind: :call, assignee_id: deal.owner_id, due_at: Time.current, title: title)
    call.update!(task: task)
  end

  def mark_returned(call)
    Outsider::Voice::Call.to_return.where(account_id: @account.id, started_at: RETURN_WINDOW.ago..)
                         .select { |missed| Outsider::Voice::PhoneNumber.same?(missed.from_number, call.to_number) }
                         .each do |missed|
      missed.update!(returned_at: call.answered_at, returned_by_id: call.user_id)
      missed.task&.complete!(call.user) unless missed.task&.completed?
    end
  end

  def log_on_deal(call)
    return unless call.opportunity

    call.opportunity.activities.create!(
      account_id: @account.id, user_id: call.user_id, kind: :call,
      metadata: { call_id: call.id, direction: call.direction, status: call.status, talk_seconds: call.talk_seconds,
                  number: call.customer_number }
    )
  end

  def broadcast(call)
    Outsider::Crm::LiveUpdates.broadcast(@account.id, 'call', id: call.id, user_id: call.user_id, contact_id: call.contact_id)
  end
end
