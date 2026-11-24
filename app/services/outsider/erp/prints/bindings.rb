# OUTSIDER: qual modelo de relatório cada caso usa, em accounts.internal_attributes (sem tabela: são poucas linhas).
# { 'os' => { 'default' => id | 'original', 'types' => { 'MANUT. CORRETIVA' => id | 'original' } }, 'quote' => { 'default' => ... } }
# - OS: pelo tipo de atendimento dela; tipo sem escolha (ou novo no ERP) usa o padrão;
# - orçamento: só o padrão;
# - 'original' é o relatório fixo, igual ao do Mais Prático (Outsider::Erp::ServiceOrderPdf / QuotePdf). É o começo de
#   tudo: nada muda no que já sai até o administrador escolher um modelo.
# Modelo apagado some das escolhas (volta para o padrão / original).
class Outsider::Erp::Prints::Bindings
  KEY = 'outsider_erp_prints'.freeze
  ORIGINAL = 'original'.freeze
  MAX_TYPES = 200

  def initialize(account)
    @account = account
  end

  def to_h
    data = stored
    Outsider::Erp::PrintTemplate::KINDS.to_h do |kind|
      entry = data[kind].to_h
      value = { 'default' => valid(kind, entry['default']) }
      value['types'] = entry['types'].to_h.transform_values { |choice| valid(kind, choice) } if kind == 'os'
      [kind, value]
    end
  end

  # escolha para um caso: id do modelo ou 'original'
  def choice(kind, attendance_type = nil)
    data = to_h[kind.to_s]
    type_choice(data, attendance_type) || data['default']
  end

  # os tipos de atendimento com modelo próprio (o botão da OS mostra o tipo: "Emitir relatório Entrega Técnica")
  def own_types(kind = 'os')
    to_h[kind.to_s].fetch('types', {}).reject { |_, choice| choice == ORIGINAL }.keys
  end

  # algum caso deste tipo usa um modelo? (não: o relatório sai pelo caminho original, sem ler nada a mais)
  def uses_templates?(kind)
    data = to_h[kind.to_s]
    [data['default'], *data.fetch('types', {}).values].any? { |choice| choice != ORIGINAL }
  end

  # o modelo do caso, ou nil para o relatório original
  def template(kind, attendance_type = nil)
    id = choice(kind, attendance_type)
    Outsider::Erp::PrintTemplate.find_by(account_id: @account.id, kind: kind.to_s, id: id) unless id == ORIGINAL
  end

  def update(kind, default:, types: nil)
    kind = kind.to_s
    raise ArgumentError, 'kind' unless Outsider::Erp::PrintTemplate::KINDS.include?(kind)

    entry = { 'default' => valid(kind, default) }
    entry['types'] = clean_types(kind, types) if kind == 'os'
    save(stored.merge(kind => entry))
    to_h
  end

  # maiúsculas, sem acento e sem espaço sobrando: "Entrega técnica" e "ENTREGA TECNICA" são o mesmo tipo
  def self.normalize_type(value) = value.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, '').squish.upcase.first(80)

  private

  def normalize_type(value) = self.class.normalize_type(value)

  def type_choice(data, attendance_type)
    type = normalize_type(attendance_type)
    return if type.blank?

    data.fetch('types', {}).find { |name, _| normalize_type(name) == type }&.last
  end

  def stored = fresh_attributes[KEY].to_h

  # lido na hora (outra tela pode ter gravado outra chave de internal_attributes)
  def fresh_attributes = Account.where(id: @account.id).pick(:internal_attributes).to_h

  # tipo sem escolha própria não é guardado (segue o padrão)
  def clean_types(kind, types)
    types.to_h.first(MAX_TYPES).each_with_object({}) do |(type, choice), map|
      name = normalize_type(type)
      next if name.blank? || choice.blank? || choice.to_s == 'default'

      map[name] = valid(kind, choice)
    end
  end

  def valid(kind, choice)
    id = choice.to_s
    return ORIGINAL unless id.match?(/\A\d+\z/) && template_ids(kind).include?(id.to_i)

    id.to_i
  end

  def template_ids(kind)
    @template_ids ||= {}
    @template_ids[kind] ||= Outsider::Erp::PrintTemplate.where(account_id: @account.id, kind: kind).pluck(:id)
  end

  def save(data)
    @account.update_columns(internal_attributes: fresh_attributes.merge(KEY => data)) # rubocop:disable Rails/SkipsModelValidations
  end
end
