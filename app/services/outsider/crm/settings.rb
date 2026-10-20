# OUTSIDER: configurações do CRM por conta. Ficam em accounts.internal_attributes, como as
# permissões da página Status, para não precisar de coluna nova numa tabela do Chatwoot.
# As automações (Outsider::Crm::Automations, StalledOpportunities e LostChain) começam desligadas.
class Outsider::Crm::Settings
  KEY = 'outsider_crm_settings'.freeze
  # nome => [tipo, padrão, faixa ou opções aceitas]
  FIELDS = {
    'max_forward_attempts' => [:integer, 3, 1..10],
    'automation_won_label' => [:label, nil],
    'automation_lost_label' => [:label, nil],
    'automation_close_tasks' => [:boolean, false],
    'automation_stalled_task' => [:boolean, false],
    'automation_stalled_days' => [:integer, 7, 1..90],
    'highlight_no_next_task' => [:boolean, false],
    # vendedor vê só os próprios negócios e os sem responsável (gestor e administrador veem todos)
    'sellers_see_own_deals' => [:boolean, false],
    # repasse em sequência (Outsider::Crm::LostChain): perdido numa unidade segue para a próxima da ordem
    'chain_enabled' => [:boolean, false],
    'chain_unit_ids' => [:unit_ids, [].freeze],
    'chain_skip_reason_ids' => [:reason_ids, [].freeze],
    # pool: fica sem responsável para um vendedor da unidade pegar; rotation: rodízio entre os vendedores
    'chain_assign' => [:choice, 'pool', %w[pool rotation].freeze]
  }.freeze
  DEFAULTS = FIELDS.transform_values(&:second).freeze
  # listas de ids: tipo => modelo de onde os ids precisam ser (da mesma conta)
  LIST_MODELS = { unit_ids: 'Outsider::Crm::BusinessUnit', reason_ids: 'Outsider::Crm::LostReason' }.freeze
  LISTS = FIELDS.select { |_name, (type)| LIST_MODELS.key?(type) }.keys.freeze
  INVALID = Object.new.freeze

  class Invalid < StandardError; end

  def initialize(account)
    @account = account
  end

  def to_h
    DEFAULTS.merge(@account.internal_attributes.fetch(KEY, {}).slice(*DEFAULTS.keys))
  end

  def [](name)
    to_h.fetch(name.to_s)
  end

  # Para o permit do controller: listas precisam de name: []
  def self.permitted
    (DEFAULTS.keys - LISTS) + [LISTS.index_with { [] }]
  end

  def update(values)
    values = values.to_h.stringify_keys.slice(*DEFAULTS.keys).to_h { |name, value| [name, cast(name, value)] }
    invalid = values.select { |_name, value| value.equal?(INVALID) }
    raise Invalid, invalid.keys.join(', ') if invalid.any?

    @account.with_lock do
      merged = @account.internal_attributes.merge(KEY => to_h.merge(values))
      # update_columns para não esbarrar nas validações de outros campos da conta
      @account.update_columns(internal_attributes: merged) # rubocop:disable Rails/SkipsModelValidations
    end
    Outsider::Crm::LiveUpdates.broadcast(@account.id, 'config')
    to_h
  end

  private

  def cast(name, value)
    type, _default, range = FIELDS.fetch(name)
    case type
    when :integer then integer(value, range)
    when :boolean then ActiveModel::Type::Boolean.new.cast(value) || false
    when :label then label(value)
    when :choice then range.include?(value.to_s) ? value.to_s : INVALID
    else ids(value, LIST_MODELS.fetch(type).constantize)
    end
  end

  def integer(value, range)
    number = Integer(value, exception: false)
    number && range.cover?(number) ? number : INVALID
  end

  # Lista de ids da conta, na ordem recebida (a ordem das unidades é a ordem do repasse)
  def ids(value, model)
    list = Array(value).compact_blank.map { |id| Integer(id, exception: false) }
    return INVALID if list.include?(nil)

    list = list.uniq
    model.where(account_id: @account.id, id: list).count == list.size ? list : INVALID
  end

  # Etiqueta do Chatwoot pelo nome; vazio desliga a automação
  def label(value)
    title = value.to_s.strip.downcase.presence
    return if title.nil?

    @account.labels.exists?(title: title) ? title : INVALID
  end
end
