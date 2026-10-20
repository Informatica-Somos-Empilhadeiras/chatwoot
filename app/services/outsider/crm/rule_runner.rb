# OUTSIDER: executa uma regra de automação (AutomationRules) num negócio: confere as condições,
# roda as ações como "Sistema" e registra na linha do tempo do negócio o que foi feito.
# Eventos (negócio criado, entrou numa etapa, ganho, perdido) chegam pelo after_commit do negócio;
# um erro numa regra vai para o log e não desfaz a gravação do negócio nem impede as outras regras.
class Outsider::Crm::RuleRunner
  def self.on_events(opportunity, events)
    Outsider::Crm::AutomationRules.new(opportunity.account).active(events).each do |rule|
      runner = new(opportunity, rule)
      runner.perform if runner.matches?
    end
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: opportunity.account).capture_exception
  end

  def initialize(opportunity, rule, key: nil)
    @opportunity = opportunity
    @rule = rule
    @key = key
  end

  def matches?
    conditions = @rule['conditions'] || {}
    same_place = %w[business_unit_id pipeline_id stage_id lost_reason_id].all? do |field|
      conditions[field].nil? || conditions[field] == @opportunity[field]
    end
    same_place && (conditions['min_value_cents'].nil? || @opportunity.value_cents >= conditions['min_value_cents'])
  end

  # key: marca da verificação de hora em hora, para a mesma situação não disparar duas vezes
  def perform
    summary = {}
    Outsider::Crm::Opportunity.transaction do
      Outsider::Crm::Automations.as_system(@opportunity) do
        # encaminhar por último: depois dele o negócio já está fechado como encaminhado
        forwards, others = @rule['actions'].partition { |action| action['type'] == 'forward' }
        (others + forwards).each { |action| run_action(action, summary) }
      end
      Outsider::Crm::Automations.log(@opportunity, 'custom', rule_id: @rule['id'], rule_name: @rule['name'], key: @key, **summary)
    end
    true
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @opportunity.account).capture_exception
    false
  end

  private

  def run_action(action, summary)
    case action['type']
    when 'create_task' then create_tasks(action, summary)
    when 'set_owner' then set_owner(action, summary)
    when 'add_label' then add_label(action, summary)
    when 'add_note' then add_note(action, summary)
    when 'forward' then forward(action, summary)
    end
  end

  def create_tasks(action, summary)
    assignees(action).each do |user|
      @opportunity.tasks.create!(
        account_id: @opportunity.account_id, kind: action['kind'], title: action['title'], description: action['description'],
        due_at: action['due_in_hours'].to_i.hours.from_now, assignee: user
      )
      summary[:tasks] = summary[:tasks].to_i + 1
    end
  end

  # Responsável do negócio (sem responsável: tarefa sem dono), gestores da unidade ou uma pessoa
  def assignees(action)
    case action['assignee']
    when 'managers'
      managers = User.where(id: Outsider::Crm::BusinessUnitMember.where(business_unit_id: @opportunity.business_unit_id, role: :manager)
                                                                 .select(:user_id)).to_a
      managers.presence || [@opportunity.owner]
    when 'user' then [User.find_by(id: action['user_id']) || @opportunity.owner]
    else [@opportunity.owner]
    end
  end

  # Só passa para quem pode ser responsável na unidade (membro ou administrador)
  def set_owner(action, summary)
    user_id = action['user_id'].to_i
    return summary[:skipped] = (Array(summary[:skipped]) + ['owner_not_member']) unless assignable?(user_id)
    return if @opportunity.owner_id == user_id

    @opportunity.update!(owner_id: user_id)
    summary[:owner] = @opportunity.owner&.name
  end

  def assignable?(user_id)
    Outsider::Crm::BusinessUnitMember.exists?(business_unit_id: @opportunity.business_unit_id, user_id: user_id) ||
      AccountUser.exists?(account_id: @opportunity.account_id, user_id: user_id, role: :administrator)
  end

  def add_label(action, summary)
    conversation = @opportunity.conversation
    title = action['label']
    return summary[:skipped] = (Array(summary[:skipped]) + ['no_conversation']) if conversation.nil?
    return summary[:skipped] = (Array(summary[:skipped]) + ['label_missing']) unless @opportunity.account.labels.exists?(title: title)

    conversation.add_labels([title]) unless conversation.label_list.include?(title)
    summary[:label] = title
  end

  # Quem pode ser responsável no destino, sem depender de um usuário logado
  SystemAccess = Struct.new(:account_id) do
    def assignable_user_ids(unit_id)
      Outsider::Crm::Access.assignable_user_ids(account_id, unit_id)
    end
  end

  # Encaminhar o perdido: se o encaminhamento é recusado (limite de tentativas, já existe negócio
  # aberto lá, unidade sem pipeline, motivo obrigatório), o negócio continua perdido e a linha do
  # tempo mostra o porquê
  def forward(action, summary)
    return summary[:skipped] = (Array(summary[:skipped]) + ['same_unit']) if action['to_business_unit_id'] == @opportunity.business_unit_id

    forwarder = Outsider::Crm::OpportunityForwarder.new(@opportunity, access: SystemAccess.new(@opportunity.account_id), user: nil,
                                                                      params: forward_params(action), lost: :forward)
    forwarder.perform
    summary[:forwarded] = { unit: forwarder.target.business_unit.name, code: forwarder.target.code }
  rescue Outsider::Crm::OpportunityForwarder::Refused => e
    summary[:forward_error] = e.code.to_s
  end

  def forward_params(action)
    {
      to_business_unit_id: action['to_business_unit_id'], pipeline_id: action['pipeline_id'], reason_id: forward_reason_id(action),
      owner_id: action['owner_id'], notes: action['notes'], create_task: action['create_task'], complete_tasks: true,
      rule_name: @rule['name']
    }
  end

  def forward_reason_id(action)
    return action['reason_id'] if action['reason_id']

    @opportunity.lost_reason_id if @opportunity.lost_reason&.kind.in?(%w[forward both])
  end

  def add_note(action, summary)
    @opportunity.activities.create!(account_id: @opportunity.account_id, kind: :note, body: action['body'])
    summary[:note] = true
  end
end
