# OUTSIDER: encaminha uma oportunidade aberta para outra unidade do grupo, numa transação só. A de
# origem fecha como encaminhada (com o motivo) e fica guardada, sem poder mudar; nasce uma nova na
# unidade destino, na mesma jornada, com o mesmo contato, conversa, título, valor e campos, na
# primeira etapa do pipeline escolhido. A tentativa fica em outsider_crm_forwards e as duas linhas do
# tempo registram o encaminhamento. Não existe etapa de aceite: o destino recebe na hora.
#
# Opções: complete_tasks conclui as tarefas pendentes da origem; create_task cria para o responsável
# do destino a tarefa de contatar o cliente, com prazo de 30 minutos (é o aviso dele: aparece na aba
# Tarefas na hora e o lembrete dispara no prazo);
# assign_conversation atribui a conversa do Chatwoot a esse responsável, pelo serviço do próprio
# Chatwoot. Nada é enviado ao cliente.
class Outsider::Crm::OpportunityForwarder
  class Refused < StandardError
    attr_reader :code

    def initialize(code, **interpolations)
      @code = code
      super(I18n.t("outsider_crm.forward.errors.#{code}", **interpolations))
    end
  end

  # prazo da tarefa "Contatar cliente": o lembrete avisa o responsável quando ele chega
  CONTACT_TASK_DUE = 30.minutes

  attr_reader :target

  # Motivo de encaminhamento só é obrigatório se a conta cadastrou algum (mesma regra da perda)
  def self.reason_required?(account_id)
    Outsider::Crm::LostReason.active.exists?(account_id: account_id, kind: [:forward, :both])
  end

  def self.reasons(account_id)
    Outsider::Crm::LostReason.active.where(account_id: account_id, kind: [:forward, :both]).ordered
  end

  def initialize(opportunity, access:, user:, params:)
    @origin = opportunity
    @access = access
    @user = user
    @params = params
  end

  def perform
    Outsider::Crm::Opportunity.transaction do
      # trava a jornada para duas pessoas não gastarem a mesma tentativa ao mesmo tempo
      @origin.journey.lock!
      @origin.lock!
      validate!
      @target = create_target
      complete_origin_tasks if flag?(:complete_tasks)
      @origin.update!(status: :forwarded, lost_reason: reason)
      forward = create_forward
      log_activities(forward)
      create_contact_task if flag?(:create_task) && @target.owner
      assign_conversation if flag?(:assign_conversation)
      forward
    end
  end

  def attempts_used
    @origin.journey.forwards.count
  end

  def max_attempts
    Outsider::Crm::Settings.new(@origin.account)[:max_forward_attempts]
  end

  private

  def validate!
    raise Refused, :not_open unless @origin.open?

    validate_destination!
    validate_reason!
    raise Refused, :notes_too_long if notes.to_s.length > 2000
    raise Refused, :invalid_owner if owner_id.present? && owner.nil?

    validate_conversation! if flag?(:assign_conversation)
  end

  def validate_destination!
    raise Refused, :invalid_unit if unit.nil?
    raise Refused.new(:limit_reached, max: max_attempts) if attempts_used >= max_attempts
    raise Refused, :duplicate_open if open_in_destination?
    raise Refused, :no_pipeline if pipeline.nil?
  end

  def validate_reason!
    raise Refused, :invalid_reason if @params[:reason_id].present? && reason.nil?
    raise Refused, :reason_required if reason.nil? && self.class.reason_required?(@origin.account_id)
  end

  def validate_conversation!
    conversation = @origin.conversation
    raise Refused, :no_conversation if conversation.nil?
    raise Refused, :no_owner_to_assign if owner.nil?

    agents = conversation.inbox.assignable_agents
    raise Refused.new(:owner_not_in_inbox, name: owner.name) unless agents.include?(owner)
    raise Refused, :conversation_forbidden unless agents.include?(@user)
  end

  def unit
    return @unit if defined?(@unit)

    @unit = Outsider::Crm::BusinessUnit.active.where(account_id: @origin.account_id).where.not(id: @origin.business_unit_id)
                                       .find_by(id: @params[:to_business_unit_id])
  end

  def pipeline
    @pipeline ||= begin
      pipelines = Outsider::Crm::Pipeline.active.where(account_id: @origin.account_id, business_unit_id: unit.id)
      @params[:pipeline_id].present? ? pipelines.find_by(id: @params[:pipeline_id]) : pipelines.ordered.first
    end
  end

  def open_in_destination?
    Outsider::Crm::Opportunity.open.exists?(account_id: @origin.account_id, contact_id: @origin.contact_id, business_unit_id: unit.id)
  end

  def reason
    return @reason if defined?(@reason)

    @reason = @params[:reason_id].present? ? self.class.reasons(@origin.account_id).find_by(id: @params[:reason_id]) : nil
  end

  def owner_id
    @params[:owner_id].presence&.to_i
  end

  def owner
    return @owner if defined?(@owner)

    @owner = (User.find_by(id: owner_id) if owner_id && @access.assignable_user_ids(unit.id).include?(owner_id))
  end

  def notes
    @params[:notes].to_s.strip.presence
  end

  def flag?(name)
    ActiveModel::Type::Boolean.new.cast(@params[name]) || false
  end

  def create_target
    Outsider::Crm::Opportunity.create!(
      account_id: @origin.account_id, journey: @origin.journey, contact_id: @origin.contact_id,
      conversation_id: @origin.conversation_id, business_unit: unit, pipeline: pipeline, stage: pipeline.first_open_stage,
      title: @origin.title, value_cents: @origin.value_cents, currency: @origin.currency,
      expected_close_on: @origin.expected_close_on, custom_fields: @origin.custom_fields,
      forwarded_from: @origin, owner: owner, created_by: @user
    )
  end

  def create_forward
    Outsider::Crm::Forward.create!(
      account_id: @origin.account_id, journey: @origin.journey, from_opportunity: @origin, to_opportunity: @target,
      from_business_unit_id: @origin.business_unit_id, to_business_unit: unit, reason: reason, notes: notes,
      requested_by: @user, decided_by: @user, decided_at: Time.current, status: :accepted,
      attempt_number: attempts_used + 1
    )
  end

  def complete_origin_tasks
    @origin.tasks.pending.find_each { |task| task.complete!(@user) }
  end

  def log_activities(forward)
    shared = { reason: reason&.name, attempt: forward.attempt_number, max: max_attempts }
    log(@origin, :forwarded, shared.merge(to_unit: unit.name, to_code: @target.code, to_opportunity_id: @target.id, owner: owner&.name))
    log(@target, :received, shared.merge(from_unit: @origin.business_unit.name, from_code: @origin.code,
                                         from_opportunity_id: @origin.id, from_owner: @origin.owner&.name, stage: @target.stage.name))
  end

  def log(opportunity, kind, metadata)
    opportunity.activities.create!(account_id: @origin.account_id, user: @user, kind: kind, body: notes, metadata: metadata.compact)
  end

  def create_contact_task
    @target.tasks.create!(
      account_id: @origin.account_id, kind: :call, due_at: CONTACT_TASK_DUE.from_now, assignee: @target.owner, created_by: @user,
      title: I18n.t('outsider_crm.forward.task_title', unit: @origin.business_unit.name), description: notes
    )
  end

  def assign_conversation
    Conversations::AssignmentService.new(conversation: @origin.conversation, assignee_id: owner.id).perform
  end
end
