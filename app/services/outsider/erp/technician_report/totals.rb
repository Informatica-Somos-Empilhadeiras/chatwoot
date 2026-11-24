# OUTSIDER: os números de cada técnico no relatório (Outsider::Erp::TechnicianReport) a partir dos pedidos faturados com
# vínculo: valor creditado (a parte dele do faturado, separado em peças e serviços), pedidos, OS, clientes, ticket médio,
# participação, prazo médio da abertura da OS até a nota, tipos de atendimento, comissão (% das Configurações) e meta.
# A linha marcada fora da soma (tipo de atendimento da OS, ver Outsider::Erp::Settings::Reports) não conta.
# O mesmo técnico em unidades diferentes (códigos diferentes) é somado pelo nome.
class Outsider::Erp::TechnicianReport::Totals
  def initialize(settings)
    @settings = settings
  end

  def technicians(sales)
    groups = Hash.new { |hash, key| hash[key] = blank }
    sales.each { |sale| sale['linhas'].each { |line| add(groups[key(line)], sale, line) unless line['fora_da_soma'] } }
    total = groups.values.sum { |row| row[:faturado] }
    groups.map { |name, row| finish(name, row, total) }.sort_by { |row| -row['faturado'] }
  end

  private

  def key(line) = (line['tecnico'].presence || "Técnico #{line['tecnico_codigo']}").to_s.squish.upcase

  def blank
    { faturado: 0.0, pecas: 0.0, servicos: 0.0, pedidos: Set.new, os: Set.new, clientes: Set.new, prazos: [], atendimentos: Hash.new(0),
      vendedores: Hash.new(0), unidades: Set.new }
  end

  def add(row, sale, line)
    share = line['parte'].to_f / 100
    %i[faturado pecas servicos].zip(%w[total pecas servicos]).each { |key, field| row[key] += sale[field] * share }
    unit = sale['unidade']
    row[:pedidos] << [unit, sale['pedido']]
    row[:os] << [unit, line['os']]
    row[:clientes] << [unit, sale['cliente_codigo']]
    row[:unidades] << unit
    count(row, sale, line)
  end

  def count(row, sale, line)
    row[:atendimentos][line['atendimento']] += 1 if line['atendimento']
    row[:vendedores][sale['vendedor']] += 1 if sale['vendedor']
    days = lead_days(line['data_os'], sale['data_nota'])
    row[:prazos] << days if days
  end

  def lead_days(opened, billed)
    return if opened.blank? || billed.blank?

    days = (Date.parse(billed.to_s) - Date.parse(opened.to_s)).to_i
    days unless days.negative?
  rescue Date::Error
    nil
  end

  def finish(name, row, total)
    { 'tecnico' => name, 'faturado' => row[:faturado].round(2), 'pecas' => row[:pecas].round(2), 'servicos' => row[:servicos].round(2),
      'pedidos' => row[:pedidos].size, 'os' => row[:os].size, 'clientes' => row[:clientes].size, 'unidades' => row[:unidades].to_a.sort,
      'atendimentos' => row[:atendimentos], 'vendedores' => row[:vendedores].sort_by { |_, count| -count }.first(5).to_h }
      .merge(rates(row, total), goal(name, row[:faturado]))
  end

  def rates(row, total)
    orders = row[:pedidos].size
    {
      'ticket_medio' => orders.positive? ? (row[:faturado] / orders).round(2) : 0,
      'participacao_pct' => total.positive? ? (row[:faturado] * 100 / total).round(1) : 0,
      'prazo_medio_dias' => row[:prazos].any? ? (row[:prazos].sum.to_f / row[:prazos].size).round(1) : nil,
      'comissao' => (row[:faturado] * @settings.report_commission_pct / 100).round(2)
    }
  end

  def goal(name, billed)
    goal = @settings.report_goals[name].to_f
    goal.positive? ? { 'meta' => goal, 'meta_pct' => (billed * 100 / goal).round(1) } : { 'meta' => nil, 'meta_pct' => nil }
  end
end
