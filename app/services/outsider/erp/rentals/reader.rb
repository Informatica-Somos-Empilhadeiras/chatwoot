# OUTSIDER: base das leituras de Locação e máquinas (detalhe do contrato, ficha da máquina, fatura de locação e o bloco do
# contato). Só leitura pelo query_execute, sempre com o banco da unidade na frente e as colunas conferidas no
# information_schema (Outsider::Erp::Schema). Aqui ficam o que as quatro usam: SELECT com as colunas que existem, UNION
# das unidades, cliente, contato do chat, nome de funcionário e a situação da máquina (Rentals::MachineStatus).
class Outsider::Erp::Rentals::Reader
  S = Outsider::Erp::Sql
  NotFound = Outsider::Erp::Records::Detail::NotFound
  # o resumo da máquina que aparece nos itens de contrato, nas faturas e no bloco do contato
  MACHINE = { 'descricao' => %w[Descricao], 'modelo' => %w[Modelo], 'serie' => %w[NSerie], 'patrimonio' => %w[NPatrimonio],
              'capacidade' => %w[CapacidadeCarga] }.freeze
  # o item do contrato (detalhecontrato): saída, retorno e o valor da máquina no contrato
  ITEM = { 'item' => %w[CodigoItem], 'maquina' => %w[CodigoEquipto], 'quantidade' => %w[Quantidade], 'unitario' => %w[PrecoUnitario],
           'valor' => %w[TotalLinha], 'saida' => %w[DataLocacao], 'retorno' => %w[DataRetorno], 'saida_prevista' => %w[PrevDataLocacao],
           'retorno_previsto' => %w[PrevDataRetorno], 'nf_remessa' => %w[CodigoNFRemessa], 'acessorios' => %w[Acessorios],
           'observacoes_item' => %w[Observacoes] }.freeze
  CONTRACT = { 'contrato' => %w[CodigoContrato], 'tipo' => %w[TipoContratos], 'contrato_status' => %w[Status],
               'cliente_codigo' => %w[CodigoCliente], 'inicio' => %w[DataInicio], 'termino' => %w[DataTermino],
               'periodicidade' => %w[periodicidadeContrato], 'parcela' => %w[Vrparcelas] }.freeze
  INVOICE = { 'numero' => %w[CodigoFatura], 'serie' => %w[Serie], 'data' => %w[DataEmissao], 'status' => %w[Status],
              'total' => %w[TotalFatura Total], 'inicio' => %w[DataInicioContratoContido_Impresso],
              'termino' => %w[DataTerminoContratoContido_Impresso] }.freeze

  def initialize(account, client: nil)
    @account = account
    @settings = Outsider::Erp::Settings.new(account)
    @client = client || Outsider::Erp::Client.new(@settings)
    @schema = Outsider::Erp::Schema.new(account, client: @client)
    @fleet = Outsider::Erp::Rentals::Fleet.new(account, client: @client)
    @machine_status = Outsider::Erp::Rentals::MachineStatus.new(@settings, @fleet)
  end

  private

  def check!(company)
    raise ArgumentError, 'empresa' unless @settings.companies.include?(company.to_s)
  end

  def run(sql)
    return [] unless sql

    @client.query_execute(sql).grep(Hash).map { |row| row.transform_values { |value| value.is_a?(String) ? value.strip.presence : value } }
  end

  def list(company, table, table_alias, mapping) = @schema.select_list(company, table, table_alias, mapping)
  def column?(company, table, name) = @schema.pick(company, table, [name]).present?

  # UNION ALL de um SELECT por unidade (o bloco devolve nil para pular a unidade), ordenado e limitado por cima
  def union(companies, order:, limit:, &)
    selects = companies.filter_map(&)
    return if selects.empty?

    "SELECT * FROM (#{selects.join(' UNION ALL ')}) X ORDER BY #{order} LIMIT #{Integer(limit)}"
  end

  # os LEFT JOIN da situação da máquina (apelido O = equipamentos), no cadastro que a unidade enxerga
  def status_joins(company) = @machine_status.joins(@fleet.base(company), @schema)

  def machine_fields(company)
    "#{list(company, 'equipamentos', 'O', MACHINE)}, #{@machine_status.status} AS situacao, #{@machine_status.fields.join(', ')}"
  end

  def customer(company, code) = Outsider::Erp::CustomerRecord.new(@account, client: @client).find(company, code)

  def contact(company, code)
    Outsider::Erp::Records::ContactFinder.new(@account).for_clients([[company, code.to_i]]).values.first || {}
  end

  def person(company, code) = Outsider::Erp::SellerName.new(@account, client: @client).for_code(company, code)

  def event(at, type, extra = {})
    { 'at' => at, 'type' => type }.merge(extra.compact)
  end

  # mais antigo primeiro; no mesmo instante, na ordem em que entrou (a tela inverte)
  def chronological(events)
    events.select { |item| item['at'].present? }.each_with_index
          .sort_by { |item, index| [Time.zone.parse(item['at'].to_s) || Time.zone.at(0), index] }.map(&:first)
  end

  def past?(value)
    time = Time.zone.parse(value.to_s)
    time.present? && time <= Time.current
  rescue ArgumentError
    false
  end
end
