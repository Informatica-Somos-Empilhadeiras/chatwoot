# OUTSIDER: o detalhe de um orçamento, OS, pedido ou nota fiscal (NF-e de produtos e NFS-e de serviços) do ERP para o
# painel ao lado da lista: cabeçalho, cliente, pessoas, itens, a corrente orçamento -> OS -> pedido -> notas
# (Outsider::Erp::Records::Chain) e a linha do tempo. Só leitura, sempre no banco da unidade e pelo número. Os campos
# são candidatos conferidos no information_schema (Outsider::Erp::Schema).
class Outsider::Erp::Records::Detail
  S = Outsider::Erp::Sql
  class NotFound < StandardError; end

  COMMON = Outsider::Erp::Records::DetailFields::COMMON
  DEFINITIONS = Outsider::Erp::Records::DetailFields::DEFINITIONS
  ITEMS = Outsider::Erp::Records::DetailFields::ITEMS

  def initialize(account, kind, client: nil)
    @account = account
    @kind = kind.to_s
    @definition = DEFINITIONS.fetch(@kind) { raise ArgumentError, 'tipo' }
    @settings = Outsider::Erp::Settings.new(account)
    @client = client || Outsider::Erp::Client.new(@settings)
    @schema = Outsider::Erp::Schema.new(account, client: @client)
  end

  def build(company, number)
    raise ArgumentError, 'empresa' unless @settings.companies.include?(company.to_s)

    header = header(company, number)
    chain = Outsider::Erp::Records::Chain.new(@account, company, schema: @schema, client: @client).build(@kind, number.to_i, header)
    header = header.merge(names(company, header))
    data = {
      'kind' => @kind, 'company' => company, 'numero' => number.to_i, 'header' => header,
      'cliente' => Outsider::Erp::CustomerRecord.new(@account, client: @client).find(company, header['cliente_codigo']),
      'itens' => items(company, number), 'chain' => chain, 'budget_record' => budget(company, number)
    }.merge(Outsider::Erp::Records::ContactFinder.new(@account).for_clients([[company, header['cliente_codigo'].to_i]]).values.first || {})
    finish(data)
  end

  # só o cabeçalho (para conferir status e "em uso" antes de abrir a edição de um orçamento)
  def header_only(company, number)
    raise ArgumentError, 'empresa' unless @settings.companies.include?(company.to_s)

    header(company.to_s, number)
  end

  # a OS no formato do espelho (Outsider::Erp::Writer confere a situação de agora antes de gravar)
  def editor_for(company, number)
    header = header_only(company, number)
    data = { 'company' => company.to_s, 'numero' => number.to_i, 'header' => header.merge(names(company.to_s, header)) }
    editor(data)
  end

  # substatus para o seletor: os das Configurações ou os que já aparecem nas OS da unidade
  def substatus_options(company)
    configured = Array(@settings.data['substatus_options'])
    return configured if configured.any?

    column = @schema.pick(company, 'os', %w[SubStatus])
    return [] unless column

    sql = "SELECT DISTINCT O.#{S.column(column)} AS valor FROM #{S.ident(company)}.os O WHERE O.#{S.column(column)} <> '' " \
          'ORDER BY valor LIMIT 80'
    @client.query_execute(sql).grep(Hash).filter_map { |row| row['valor'].to_s.squish.presence }.uniq
  end

  # orçamento gravado pode ser editado pelo chat só em NEGOCIAÇÃO e se ninguém estiver com ele aberto no Mais Prático
  # (o ERP marca OrcamentoEmUtilizacao; marca antiga, sem data recente, não conta)
  IN_USE_WINDOW = 8.hours

  def self.in_use?(header)
    return false unless header['em_uso'].to_i == 1

    since = Time.zone.parse(header['em_uso_desde'].to_s)
    since.present? && since > IN_USE_WINDOW.ago
  rescue ArgumentError
    false
  end

  private

  def finish(data)
    budget = data.delete('budget_record')
    timeline = Outsider::Erp::Records::Timeline.new(@account).build(data.merge('budget_record' => budget, 'attribution' => attribution(data)))
    data.merge('timeline' => timeline,
               'budget_id' => budget&.id, 'revising' => budget&.revising? == true).merge(kind_extras(data))
  end

  def kind_extras(data)
    header = data['header']
    case @kind
    when 'quotes'
      in_use = self.class.in_use?(header)
      { 'edit' => { 'allowed' => header['status'] == 'NEGOCIAÇÃO' && !in_use, 'in_use_by' => (header['em_uso_por'] if in_use) } }
    when 'orders' then { 'editor' => editor(data), 'substatus_options' => substatus_options(data['company']), 'schedules' => schedules(data) }
    else {}
    end
  end

  # os próximos agendamentos da OS nas agendas (Outsider::Erp::OrderScheduler), para o painel mostrar
  def schedules(data)
    Outsider::Erp::OrderSchedule.where(account_id: @account.id).for_order(data['company'], data['numero'])
                                .where(ends_at: Time.current..).order(:starts_at).limit(3).map do |row|
      zone = ActiveSupport::TimeZone[row.time_zone.to_s] || ActiveSupport::TimeZone['America/Sao_Paulo']
      { 'start' => row.starts_at.in_time_zone(zone).strftime('%Y-%m-%dT%H:%M:%S'), 'all_day' => row.all_day,
        'providers' => row.providers }
    end
  end

  # a OS no formato que o editor de OS (ErpOrderEditor) já usa, para editar pelo painel
  def editor(data)
    header = data['header']
    {
      'Empresa' => data['company'], 'CodigoOS' => data['numero'], 'Situacao' => header['status'], 'SubStatus' => header['substatus'],
      'TipoAtendimento' => header['atendimento'], 'TecnicoAtual' => header['tecnico'], 'NomeTecnico' => header['tecnico_nome'],
      'Defeitos' => header['defeitos'], 'Observacoes' => header['observacoes'], 'Acessorios' => header['acessorios'],
      'DataPrevisao' => header['previsao'], 'DataValidade' => header['validade']
    }
  end

  # pedido de venda: o técnico e a OS informados no chat (Outsider::Erp::SaleAttributor) entram na linha do tempo
  def attribution(data)
    return unless @kind == 'sales'

    Outsider::Erp::SaleAttribution.find_by(account_id: @account.id, company: data['company'], order_number: data['numero'])
  end

  def budget(company, number)
    return unless @kind == 'quotes'

    Outsider::Erp::Budget.where(account_id: @account.id, company: company, erp_number: number.to_i).order(:id).last
  end

  def header(company, number)
    row = @client.query_execute(header_sql(company, number)).grep(Hash).first || raise(NotFound, number.to_s)
    adjust(row.transform_values { |value| value.is_a?(String) ? value.strip : value })
  end

  def adjust(row)
    case @kind
    when 'sales' then row['status'].blank? ? row.merge('status' => sale_status(row)) : row
    when 'invoices' then row.merge(fiscal_key(row['chave']))
    when 'service_invoices' then service_header(row)
    else row
    end
  end

  # chave de 44 dígitos: série nas posições 23-25 e número nas 26-34
  def fiscal_key(key)
    digits = key.to_s.gsub(/\D/, '')
    return {} unless digits.length == 44

    { 'serie' => digits[22, 3].to_i, 'numero_nf' => digits[25, 9].to_i }
  end

  # destinatário que não é cliente (fornecedor) não tem cadastro em clientes
  def service_header(row)
    row = row.merge('cliente_codigo' => nil) if row.key?('e_cliente') && row['e_cliente'].to_i.zero?
    row
  end

  def header_sql(company, number)
    table = @definition[:table]
    key = @schema.pick(company, table, @definition[:key]) || raise(NotFound, number.to_s)
    "SELECT #{@schema.select_list(company, table, 'O', COMMON.merge(@definition[:header]).compact)} " \
      "FROM #{S.ident(company)}.#{S.ident(table)} O WHERE O.#{S.column(key)} = #{S.int(number)}"
  end

  def sale_status(row) = row['fechado'].to_i.zero? ? 'ABERTO' : 'FECHADO'

  # nomes das pessoas (vendedor, técnico, quem criou) pelo cadastro de funcionários
  def names(company, header)
    seller = Outsider::Erp::SellerName.new(@account, client: @client)
    names = %w[vendedor tecnico iniciado_por autorizado_por].each_with_object({}) do |key, map|
      map["#{key}_nome"] = seller.for_code(company, header[key]) if header[key].to_i.positive?
    end
    names.merge(payment_name(header['pagamento']))
  end

  # o ERP guarda a forma de pagamento como texto: em geral o nome, às vezes só o código ("1"); o código vira o nome
  def payment_name(value)
    return {} unless value.to_s.strip.match?(/\A\d+\z/)

    name = Outsider::Erp::PaymentTerms.new(@account).name(value)
    name.present? ? { 'pagamento' => name } : {}
  end

  def items(company, number)
    table = @definition[:items_table]
    key = @schema.pick(company, table, @definition[:items_key])
    return [] unless key

    sql = "SELECT D.CodigoProduto AS codigo, #{@schema.select_list(company, table, 'D', ITEMS)}, #{product_fields(company)} " \
          "FROM #{S.ident(company)}.#{S.ident(table)} D LEFT JOIN #{S.ident(company)}.produtos P ON P.CodigoProduto = D.CodigoProduto " \
          "WHERE D.#{S.column(key)} = #{S.int(number)} ORDER BY D.CodigoItem"
    @client.query_execute(sql).grep(Hash).map { |row| item(row) }
  end

  def product_fields(company)
    { 'descricao' => %w[Descricao DescricaoProduto Nome], 'tipo' => %w[Tipo], 'unidade' => %w[Unidade] }.map do |key, candidates|
      column = @schema.pick(company, 'produtos', candidates)
      column ? "P.#{S.column(column)} AS #{key}" : "NULL AS #{key}"
    end.join(', ')
  end

  def item(row)
    {
      'codigo' => row['codigo'].to_i, 'descricao' => row['descricao'].to_s.squish, 'servico' => row['tipo'].to_i == 1,
      'unidade' => row['unidade'].to_s.strip, 'quantidade' => row['quantidade'].to_f, 'unitario' => row['unitario'].to_f,
      'desconto' => row['desconto'].to_f, 'total' => row['total'].to_f.round(2)
    }
  end
end
