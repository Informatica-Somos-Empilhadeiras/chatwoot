# OUTSIDER: as contagens das listas da seção ERP (abas rápidas, unidades, vendedores/técnicos, total e soma) a partir das
# linhas agrupadas que Outsider::Erp::Records::Query#facets_sql devolve. Cada contagem aplica os outros filtros escolhidos
# (a aba "Fechados" mostra quantos fechados há na unidade e vendedor escolhidos), sem nova ida ao ERP.
class Outsider::Erp::Records::Facets
  def initialize(kind, rows, mine: nil)
    @kind = kind
    @mine = mine
    @rows = rows.map { |row| normalize(row) }
  end

  def as_json(view:, company:, person:)
    selected = matching(view: view, company: company, person: person)
    {
      views: views(company, person), companies: companies(view, person), people: people(view, company),
      total: selected.sum { |row| row[:qtd] }, sum: selected.sum { |row| row[:soma] }.round(2)
    }
  end

  def matching(view:, company:, person:)
    @rows.select { |row| match?(row, view: view, company: company, person: person) }
  end

  private

  def normalize(row)
    {
      banco: row['banco'].to_s, status: row['status'].to_s.strip.presence, pessoa_codigo: row['pessoa_codigo'].to_i,
      pessoa: row['pessoa'].to_s.squish.presence, atrasada: row['atrasada'].to_i == 1, qtd: row['qtd'].to_i,
      soma: row['soma'].to_f
    }
  end

  def match?(row, view:, company:, person:)
    (company.blank? || row[:banco] == company) && (person.to_i <= 0 || row[:pessoa_codigo] == person.to_i) &&
      in_view?(row, view)
  end

  def in_view?(row, view)
    return true unless view
    return view[:status_in].include?(row[:status]) if view[:status_in]
    return view[:status_not_in].exclude?(row[:status]) if view[:status_not_in]
    return row[:atrasada] if view[:late]
    return @mine.present? && row[:pessoa_codigo] == @mine.to_i if view[:mine]

    true
  end

  # as do tipo (sem "Meus" para quem não tem código do ERP); pedidos: "Todos" + as situações que aparecem
  def views(company, person)
    view_definitions.map do |view|
      { key: view[:key], label: view[:label], count: matching(view: view, company: company, person: person).sum { |row| row[:qtd] } }
    end
  end

  def view_definitions
    definitions = @kind.views.reject { |view| view[:mine] && @mine.blank? }
    return definitions unless @kind.is_a?(Outsider::Erp::Records::SaleKind)

    definitions + statuses.map { |status| { key: "status:#{status}", status_in: [status], label: status } }
  end

  def statuses
    @rows.select { |row| row[:status] }.group_by { |row| row[:status] }.sort_by { |_status, rows| -total(rows) }.map(&:first)
  end

  def total(rows) = rows.sum { |row| row[:qtd] }

  def companies(view, person)
    @rows.select { |row| match?(row, view: view, company: nil, person: person) }.group_by { |row| row[:banco] }
         .map { |company, rows| { value: company, count: total(rows) } }.sort_by { |item| -item[:count] }
  end

  def people(view, company)
    @rows.select { |row| row[:pessoa_codigo].positive? && match?(row, view: view, company: company, person: nil) }
         .group_by { |row| row[:pessoa_codigo] }
         .map { |code, rows| { code: code, name: person_name(code, rows), count: total(rows) } }
         .sort_by { |item| item[:name] }
  end

  def person_name(code, rows) = rows.filter_map { |row| row[:pessoa] }.first || "##{code}"
end
