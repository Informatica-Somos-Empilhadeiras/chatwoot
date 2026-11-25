# OUTSIDER: uma página de uma lista da seção ERP (orçamentos, OS ou pedidos) com as contagens. Duas consultas ao ERP:
# as contagens agrupadas e a página. Cada linha volta com o contato do chat ligado àquele cliente do ERP (para "Abrir no
# chat") e, nos orçamentos, o rascunho/registro do chat quando ele foi feito aqui.
class Outsider::Erp::Records::Lister
  PER_DEFAULT = 50
  PER_MAX = 100
  READ_TIMEOUT = 20

  def initialize(account, kind_name, user: nil, client: nil)
    @account = account
    @user = user
    @settings = Outsider::Erp::Settings.new(account)
    @client = client || Outsider::Erp::Client.new(@settings)
    @kind = Outsider::Erp::Records::Kind.for(kind_name, @settings, client: @client)
    @query = Outsider::Erp::Records::Query.new(@kind, Outsider::Erp::Schema.new(account, client: @client))
  end

  # params: q, from, to, view, company, person, clients ([[empresa, código]]), page, per, sort, direction e os filtros
  # extras do tipo (OS: atendimento, vendedor)
  def page(params)
    view = @kind.view(params[:view])
    company = company(params[:company])
    base = base_filters(params)
    counts = facets(base).as_json(view: view, company: company, person: params[:person])
    per = per(params[:per])
    page = [params[:page].to_i, 1].max
    filters = base.merge(view: view, person: params[:person], mine: mine)
    items = rows(company, filters, params, per, page)
    counts.merge(view: view[:key], page: page, per: per, items: enrich(items), dimensions: dimensions(company, filters))
  end

  private

  def company(value) = companies.include?(value.to_s) ? value.to_s : nil
  def companies = @companies ||= @kind.companies(@settings.companies)

  def base_filters(params)
    { q: params[:q], from: params[:from], to: params[:to], clients: clients(params[:clients]), machine: machine(params[:machine]),
      dimensions: @kind.dimensions.keys.index_with { |key| params[key].presence }.compact }
  end

  def facets(base)
    Outsider::Erp::Records::Facets.new(@kind, run(@query.facets_sql(companies, base)), mine: mine)
  end

  def rows(company, filters, params, per, page)
    options = { sort: params[:sort], direction: params[:direction], per: per, offset: (page - 1) * per }
    sql = @query.page_sql(company ? [company] : companies, filters, options)
    run(sql).map { |row| item(row) }
  end

  # { atendimento: [{ value:, count: }], vendedor: [{ value:, name:, count: }] } em ordem alfabética
  def dimensions(company, filters)
    return {} if @kind.dimensions.empty?

    rows = run(@query.dimensions_sql(company ? [company] : companies, filters)).group_by { |row| row['dim'].to_s }
    @kind.dimensions.keys.index_with do |key|
      rows.fetch(key.to_s, []).map { |row| dimension_item(row) }.sort_by { |item| (item[:name] || item[:value]).to_s }
    end
  end

  def dimension_item(row)
    value = row['valor']
    { value: value.is_a?(String) ? value.squish : value, name: row['nome'].to_s.squish.presence, count: row['qtd'].to_i }
  end

  def run(sql)
    return [] unless sql

    @client.query_execute(sql, read_timeout: READ_TIMEOUT).grep(Hash)
  end

  def per(value)
    value = value.to_i
    value.between?(1, PER_MAX) ? value : PER_DEFAULT
  end

  # só empresas das Configurações e códigos numéricos
  def clients(list)
    return if list.nil?

    Array(list).filter_map do |row|
      company, code = row.is_a?(Hash) ? row.with_indifferent_access.values_at(:empresa, :codigo) : row
      [company.to_s, code.to_i] if @settings.companies.include?(company.to_s) && code.to_i.positive?
    end
  end

  # "somosemp:18110" (cadastro base da máquina): as OS dela em todas as unidades que enxergam aquele cadastro
  def machine(value)
    base, number = value.to_s.split(':', 2)
    return unless @kind.columns.key?(:maquina) && number.to_i.positive? && @settings.companies.include?(base.to_s)

    { companies: Outsider::Erp::Rentals::Fleet.new(@account, client: @client).members(base) & companies, number: number.to_i }
  end

  # código do ERP de quem está vendo (Configurações > pessoas do chat x código do ERP)
  def mine
    @mine ||= Integer(@settings.data['user_erp_ids'].to_h[@user&.id.to_s].to_s, exception: false)
  end

  def item(row)
    row = row.transform_values { |value| value.is_a?(String) ? value.squish : value }
    row.merge('numero' => row['numero'].to_i, 'total' => row['total'].to_f.round(2), 'cliente_codigo' => row['cliente_codigo'].to_i,
              'pessoa_codigo' => row['pessoa_codigo'].to_i)
  end

  def enrich(items)
    contacts = Outsider::Erp::Records::ContactFinder.new(@account).for_clients(items.map { |row| [row['banco'], row['cliente_codigo']] })
    budgets = @kind.is_a?(Outsider::Erp::Records::QuoteKind) ? chat_budgets(items) : {}
    items.map do |row|
      row.merge(contacts[[row['banco'], row['cliente_codigo']]] || {}).merge('budget_id' => budgets[[row['banco'], row['numero']]])
    end
  end

  def chat_budgets(items)
    return {} if items.empty?

    Outsider::Erp::Budget.where(account_id: @account.id, company: items.pluck('banco').uniq, erp_number: items.pluck('numero'))
                         .pluck(:company, :erp_number, :id).to_h { |company, number, id| [[company, number], id] }
  end
end
