# OUTSIDER: relatório de desempenho dos técnicos (seção ERP, Relatórios). Base: pedidos de venda FATURADOS no período,
# ou seja, com nota de saída válida (NF-e ou NFS-e, não cancelada) emitida entre as datas; pedido sem nota não entra.
# O técnico vem do vínculo informado pelo vendedor no chat (Outsider::Erp::SaleAttribution), porque o pedido do Mais
# Prático não tem técnico nem OS; sem ele, das OS que o próprio ERP liga ao pedido. Cada técnico recebe a parte dele do
# valor faturado (NF-e = peças, NFS-e = serviços). Também mostra o que ficou de fora: pedidos faturados sem técnico e
# pedidos com técnico que ainda não foram faturados. A parte de uma OS de tipo fora da soma (Configurações: garantia,
# entrega técnica, frotas) aparece no pedido, marcada, mas não entra nos números do técnico. Só leitura no ERP; o
# resultado fica guardado alguns minutos.
class Outsider::Erp::TechnicianReport
  MAX_DAYS = 400
  CACHE_TTL = 5.minutes
  PENDING_DAYS = 180
  LIST_LIMIT = 300

  def initialize(account)
    @account = account
    @settings = Outsider::Erp::Settings.new(account)
    @lookup = Outsider::Erp::SaleLookup.new(account)
  end

  # from/to: Date (a data da nota); companies: unidades (vazio = todas as das Configurações)
  def build(from:, to:, companies: [])
    raise ArgumentError, 'periodo' unless from <= to && (to - from).to_i <= MAX_DAYS

    units = companies.presence ? @settings.companies & companies : @settings.companies
    Rails.cache.fetch(cache_key(from, to, units), expires_in: CACHE_TTL) { compute(from, to, units).merge('unidades' => units) }
  end

  private

  def cache_key(from, to, units)
    stamp = Outsider::Erp::SaleAttribution.where(account_id: @account.id).maximum(:updated_at).to_i
    ['outsider-technician-report', @account.id, from, to, units.sort, stamp, @settings.report_commission_pct, @settings.report_goals,
     @settings.report_excluded_types]
  end

  def compute(from, to, units)
    units = units.map { |company| Outsider::Erp::TechnicianReport::Unit.new(@account, @lookup, company) }
    attributed, unattributed = units.flat_map { |unit| unit.sales(from, to) }.partition { |sale| sale['linhas'].any? }
    mark_excluded(attributed)
    pending = units.flat_map { |unit| unit.pending(PENDING_DAYS.days.ago) }
    technicians = Outsider::Erp::TechnicianReport::Totals.new(@settings).technicians(attributed)
    {
      'periodo' => { 'de' => from.iso8601, 'ate' => to.iso8601 }, 'comissao_pct' => @settings.report_commission_pct,
      'resumo' => summary(attributed, unattributed, pending).merge(team(technicians)), 'tecnicos' => technicians,
      'pedidos' => attributed.first(2_000), 'sem_tecnico' => biggest(unattributed), 'aguardando' => biggest(pending)
    }
  end

  # cada linha (técnico x OS) diz se fica fora da soma pelo tipo de atendimento da OS
  def mark_excluded(sales)
    sales.each { |sale| sale['linhas'].each { |line| line['fora_da_soma'] = @settings.report_excluded?(line['atendimento']) } }
  end

  def biggest(sales) = sales.sort_by { |sale| -sale['total'] }.first(LIST_LIMIT)

  def team(technicians) = { 'comissao' => technicians.sum { |row| row['comissao'] }.round(2), 'tecnicos' => technicians.size }

  def summary(attributed, unattributed, pending)
    credited = sum(attributed)
    total = credited + sum(unattributed)
    {
      'faturado' => total.round(2), 'pedidos' => attributed.size + unattributed.size, 'faturado_com_tecnico' => credited.round(2),
      'pedidos_com_tecnico' => attributed.size, 'pedidos_tecnico_erp' => attributed.count { |sale| sale['origem'] == 'erp' },
      'cobertura_pct' => total.positive? ? (credited * 100 / total).round(1) : 0,
      'sem_tecnico_valor' => sum(unattributed).round(2), 'sem_tecnico_pedidos' => unattributed.size,
      'aguardando_valor' => sum(pending).round(2), 'aguardando_pedidos' => pending.size
    }.merge(excluded_summary(attributed))
  end

  # quanto ficou fora da soma dos técnicos pelo tipo de atendimento
  def excluded_summary(sales)
    parts = sales.flat_map { |sale| sale['linhas'].select { |line| line['fora_da_soma'] }.map { |line| [sale, line] } }
    {
      'fora_da_soma_valor' => parts.sum { |sale, line| sale['total'] * line['parte'].to_f / 100 }.round(2),
      'fora_da_soma_pedidos' => parts.map { |sale, _| [sale['unidade'], sale['pedido']] }.uniq.size,
      'fora_da_soma_tipos' => @settings.report_excluded_types
    }
  end

  def sum(sales) = sales.sum { |sale| sale['total'] }
end
