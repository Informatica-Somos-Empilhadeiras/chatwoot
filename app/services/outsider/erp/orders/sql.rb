# OUTSIDER: monta as SQL que gravam no ERP uma OS feita no chat (Outsider::Erp::OrderDraft). O Mais Prático não tem
# função de OS: o desktop e o app gravam direto nas tabelas os, detalheos e historicoos, e aqui fazemos o mesmo, do
# jeito que o levantamento de 25/11/2026 mostrou (descoberta-criar-os*-saida.txt). Puro: não executa nada (quem roda é
# Outsider::Erp::Orders::Creator, via Client#query_execute). Todo valor passa pelo Outsider::Erp::Sql e toda tabela leva
# o banco da unidade na frente.
#
# Travas que valem em toda escrita:
# - número = maior + 1 calculado no próprio INSERT (o número é chave única: se o escritório pegar o mesmo no mesmo
#   instante, o banco recusa o nosso e quem chama tenta de novo);
# - a OS leva a marca do rascunho em CodigoPedidoOutroSistema e o INSERT só entra se ainda não houver OS com ela; tudo o
#   que vem depois (linhas, histórico, somas) só mexe na OS que tem essa marca;
# - o orçamento só é reservado se ninguém estiver com ele aberto no Mais Prático e só é fechado se a reserva ainda for
#   nossa (OrcamentoEmUtilizacao/NomeUserEmUtilizacao, o mesmo aviso que o desktop usa).
class Outsider::Erp::Orders::Sql
  S = Outsider::Erp::Sql
  NEGOTIATION = 'NEGOCIAÇÃO'.freeze
  CLOSED = 'FECHADO'.freeze
  APP_SUBSTATUS = 'APONTAMENTOS MOBILE - PENDENTE'.freeze
  BILLING = 'COBRANÇA BANCÁRIA'.freeze
  IN_USE_HOURS = 8
  # cabeçalho do orçamento que a conversão do desktop copia para a OS (coluna da OS => coluna do orçamento); entram só as
  # que existem nas duas tabelas desta unidade
  QUOTE_HEADER = {
    'Vendedor' => 'Vendedor', 'Observacoes' => 'Observacoes', 'DescontoTotal' => 'descontototal', 'TotalServicos' => 'totalServicos',
    'Total' => 'total', 'ValorExtenso' => 'ValorExtenso', 'FormaPagto' => 'FormaPagto', 'QtdParcelas' => 'qtdparcelas',
    'Indice' => 'indice', 'VrParcelas' => 'vrparcelas', 'CodigoTransportadora' => 'CodigoTransportadora',
    'VrTotalTributos' => 'VrTotalTributos', 'EnderecoEntr' => 'EnderecoEntr', 'BairroEntr' => 'BairroEntr', 'NumeroEntr' => 'NumeroEntr',
    'CidadeEntr' => 'CidadeEntr', 'ReferenciaEntr' => 'ReferenciaEntr', 'CepEntr' => 'CepEntr', 'UFEntr' => 'UFEntr',
    'ComplementoEntr' => 'ComplementoEntr', 'Email' => 'email', 'PedidoCliente' => 'PedidoCliente', 'TipoFrete' => 'TipoFrete'
  }.freeze
  # colunas das linhas do orçamento que a conversão NÃO copia: renumeradas, recalculadas (impostos, ver ITEM_TAXES) ou que
  # o desktop deixa de fora (preço líquido, tributos por linha, preço objetivo/mínimo, difal); custo médio só de peça
  ITEM_SKIP = %w[codigoorcamento codigoos codigoitem ordem baseicms vricms vrpis vrcofins vrprodunliq vrprodliq vrtotaltributoslinha
                 tributavel precovendaobjetivo precovendaminimo customedio ckvendaexterna incluidomobile percbaseicmsdestino
                 percaliqufenvolvido baseicmsdifaldentro convertido codigointegracaomobile timestamp tstamp].freeze
  # impostos da linha como a OS convertida do desktop grava (conferido nos itens já convertidos, sem arredondar): base do
  # ICMS = total x % da base, ICMS = base x alíquota, PIS e COFINS sobre o total cheio. Sem o percentual fica NULL, como lá.
  ITEM_TAXES = {
    'BaseICMS' => 'D.`TotalLinha` * D.`PercBaseICMS` / 100',
    'VrICMS' => 'D.`TotalLinha` * D.`PercBaseICMS` / 100 * D.`aliqicms` / 100',
    'VrPIS' => 'D.`TotalLinha` * D.`AliqPIS` / 100',
    'VrCofins' => 'D.`TotalLinha` * D.`AliqCofins` / 100'
  }.freeze

  # erp_user: código de funcionário do ERP de quem grava (Atendente, IDLogado, histórico, quem converteu)
  def initialize(draft, erp_user:, lock_name: nil)
    @draft = draft
    @erp_user = Integer(erp_user)
    @lock_name = lock_name
  end

  def bank = S.ident(@draft.company)
  def marker = S.str(@draft.marker)
  def number_sql = 'SELECT IFNULL(MAX(`CodigoOS`), 0) + 1 AS proximo'

  # a OS deste rascunho, se já entrou (pela marca)
  def find_sql
    'SELECT O.`CodigoOS` AS numero, O.`Situacao` AS situacao, O.`TipoAtendimento` AS tipo, O.`CodigoCliente` AS cliente, ' \
      "O.`Tecnico` AS tecnico, O.`CodigoMaquina` AS maquina, O.`NSerie` AS serie, O.`Orcamento` AS orcamento FROM #{bank}.os O " \
      "WHERE O.`CodigoPedidoOutroSistema` = #{marker} ORDER BY O.`CodigoOS` LIMIT 2"
  end

  # Nova OS: pré-OS como a do app (cabeçalho + peças; impostos e totais o escritório calcula ao abrir e salvar no Mais
  # Prático), com o usuário e o documento do cliente como o desktop preenche
  def fresh_header_sql
    values = common_header.merge(
      'Vendedor' => S.int(@erp_user), 'Defeitos' => text('defeitos', 5000).then { |value| value == 'NULL' ? "'.'" : value },
      'Observacoes' => text('observacoes', 5000), 'DataEntrada' => 'NOW()'
    )
    insert_header(values, "FROM #{bank}.clientes C #{number_join} #{machine_join} WHERE C.`CodigoCliente` = #{S.int(@draft.customer_code)}")
  end

  # conversão: o cabeçalho do orçamento (QUOTE_HEADER, as colunas que existem nos dois lados) + o que a tela pede + o que
  # o desktop preenche sozinho (entrada só com o dia, atendente, documento do cliente, defeitos ".", título de cobrança)
  def conversion_header_sql(os_columns, quote_columns)
    os_set = os_columns.to_set(&:downcase)
    quote_set = quote_columns.to_set(&:downcase)
    copied = QUOTE_HEADER.select { |os_col, quote_col| os_set.include?(os_col.downcase) && quote_set.include?(quote_col.downcase) }
                         .transform_values { |quote_col| "Q.#{S.column(quote_col)}" }
    values = copied.merge(common_header).merge(
      'Orcamento' => 'Q.`codigoorcamento`', 'CodigoCliente' => 'Q.`CodigoCliente`', 'DataEntrada' => 'CURDATE()',
      'Defeitos' => text('defeitos', 5000).then { |value| value == 'NULL' ? "'.'" : value }, 'Consumo' => '0', 'Classificacao' => '1'
    )
    values['Observacoes'] = "IFNULL(Q.`Observacoes`, #{text('observacoes', 5000)})" if copied.key?('Observacoes')
    values['TipoTitulo'] = S.str(BILLING)
    values.select! { |column, _value| os_set.include?(column.downcase) }
    insert_header(values, "FROM #{bank}.orcamento Q JOIN #{bank}.clientes C ON C.`CodigoCliente` = Q.`CodigoCliente` #{number_join} " \
                          "#{machine_join} WHERE Q.`codigoorcamento` = #{S.int(@draft.quote_number)} AND #{reserved_guard}")
  end

  # histórico inicial, igual ao desktop: linha 1 a situação NEGOCIAÇÃO (Origem STATUS) e linha 2 o tipo de atendimento
  def history_sql(number, origin)
    value = origin == 'STATUS' ? NEGOTIATION : @draft.fields['tipo_atendimento'].to_s.first(255)
    "INSERT INTO #{bank}.historicoos (`Codigo`, `CodigoItem`, `Situacao`, `HoraStatus`, `IdLogado`, `Origem`) " \
      "SELECT O.`CodigoOS`, M.proximo, #{S.str(value)}, NOW(), #{S.int(@erp_user)}, #{S.str(origin)} FROM #{bank}.os O " \
      "JOIN (SELECT IFNULL(MAX(`CodigoItem`), 0) + 1 AS proximo FROM #{bank}.historicoos WHERE `Codigo` = #{S.int(number)}) M " \
      "WHERE O.`CodigoOS` = #{S.int(number)} AND O.`CodigoPedidoOutroSistema` = #{marker} AND NOT EXISTS " \
      "(SELECT 1 FROM #{bank}.historicoos H WHERE H.`Codigo` = #{S.int(number)} AND H.`Origem` = #{S.str(origin)})"
  end

  def history_count_sql(number)
    "SELECT COUNT(*) AS linhas FROM #{bank}.historicoos WHERE `Codigo` = #{S.int(number)}"
  end

  # Nova OS: uma linha por item, como as que o app sincroniza (marcadas como incluídas pelo mobile, sem imposto). Só entra
  # se o produto existir; linha que já está lá (tentativa que caiu) não entra de novo
  def fresh_item_sql(number, position, item)
    total = S.dec(Outsider::Erp::OrderDraft.line_total(item))
    "INSERT INTO #{bank}.detalheos (`CodigoOS`, `CodigoItem`, `Ordem`, `CodigoProduto`, `Quantidade`, `precounitario`, `TotalLinha`, " \
      "`IncluidoMobile`) SELECT O.`CodigoOS`, #{S.int(position)}, #{S.int(position)}, P.`CodigoProduto`, #{S.dec(item['quantidade'])}, " \
      "#{S.dec(item['preco'])}, #{total}, 1 FROM #{bank}.os O JOIN #{bank}.produtos P ON P.`CodigoProduto` = #{S.int(item['codigo'])} " \
      "WHERE #{own_order(number)} AND #{free_line(number, position)}"
  end

  # conversão: a linha do orçamento copiada (colunas em comum) com a nova numeração, os impostos recalculados e a marca
  # de venda externa; custo médio só para peça (o desktop deixa vazio no serviço)
  def conversion_item_sql(number, position, quote_item, copy_columns, os_columns)
    os_set = os_columns.to_set(&:downcase)
    targets = %w[CodigoOS CodigoItem Ordem] + copy_columns
    values = ['O.`CodigoOS`', S.int(position), S.int(position)] + copy_columns.map { |column| "D.#{S.column(column)}" }
    ITEM_TAXES.each do |column, formula|
      next unless os_set.include?(column.downcase)

      targets << column
      values << formula
    end
    targets, values = add_item_extras(targets, values, os_set)
    "INSERT INTO #{bank}.detalheos (#{targets.map { |column| S.column(column) }.join(', ')}) SELECT #{values.join(', ')} " \
      "FROM #{bank}.os O JOIN #{bank}.detalheorcamento D ON D.`CodigoOrcamento` = #{S.int(@draft.quote_number)} " \
      "AND D.`CodigoItem` = #{S.int(quote_item)} LEFT JOIN #{bank}.produtos P ON P.`CodigoProduto` = D.`CodigoProduto` " \
      "WHERE #{own_order(number)} AND #{free_line(number, position)}"
  end

  # colunas das linhas que passam do orçamento para a OS nesta unidade (as que existem nas duas, menos ITEM_SKIP)
  def self.copy_columns(quote_item_columns, os_item_columns)
    os_set = os_item_columns.index_by(&:downcase)
    quote_item_columns.filter_map { |column| os_set[column.downcase] && column }
                      .reject { |column| ITEM_SKIP.include?(column.downcase) || ITEM_TAXES.keys.map(&:downcase).include?(column.downcase) }
                      .select { |column| column.match?(S::COLUMN) }
  end

  def quote_items_sql
    'SELECT D.`CodigoItem` AS item, D.`CodigoProduto` AS produto, D.`Quantidade` AS quantidade, D.`TotalLinha` AS total ' \
      "FROM #{bank}.detalheorcamento D WHERE D.`CodigoOrcamento` = #{S.int(@draft.quote_number)} ORDER BY D.`CodigoItem`"
  end

  def lines_sql(number)
    "SELECT D.`CodigoItem` AS item, D.`CodigoProduto` AS produto FROM #{bank}.detalheos D WHERE D.`CodigoOS` = #{S.int(number)} " \
      'ORDER BY D.`CodigoItem`'
  end

  # conversão: as somas dos impostos das linhas no cabeçalho, arredondadas em 2 casas como o desktop, e o total de peças
  def conversion_sums_sql(number, os_columns)
    os_set = os_columns.to_set(&:downcase)
    sums = { 'VrPis' => 'ROUND(SUM(D.`VrPIS`), 2)', 'VrCofins' => 'ROUND(SUM(D.`VrCofins`), 2)', 'BaseICMS' => 'ROUND(SUM(D.`BaseICMS`), 2)',
             'VrICMS' => 'ROUND(SUM(D.`VrICMS`), 2)',
             'TotalProdutos' => 'ROUND(SUM(CASE WHEN IFNULL(P.`Tipo`, 0) = 1 THEN 0 ELSE D.`TotalLinha` END), 2)' }
           .select { |column, _sql| os_set.include?(column.downcase) }
    return if sums.empty?

    selects = sums.map { |column, sql| "#{sql} AS #{column.downcase}" }.join(', ')
    sets = sums.keys.map { |column| "O.#{S.column(column)} = T.#{column.downcase}" }.join(', ')
    "UPDATE #{bank}.os O JOIN (SELECT #{selects} FROM #{bank}.detalheos D LEFT JOIN #{bank}.produtos P ON P.`CodigoProduto` = " \
      "D.`CodigoProduto` WHERE D.`CodigoOS` = #{S.int(number)}) T SET #{sets} WHERE #{own_order(number)}"
  end

  # orçamento como está agora: situação, ligações, aviso de uso e itens
  def quote_state_sql
    'SELECT Q.`codigoorcamento` AS numero, Q.`Status` AS status, Q.`CodigoCliente` AS cliente, Q.`OrdemServico` AS os, ' \
      "#{quote_order_link}, Q.`total` AS total, IFNULL(Q.`OrcamentoEmUtilizacao`, 0) AS em_uso, " \
      "Q.`NomeUserEmUtilizacao` AS em_uso_por, IFNULL(Q.`DataEmUtilizacao` > NOW() - INTERVAL #{IN_USE_HOURS} HOUR, 0) AS em_uso_recente, " \
      "(SELECT COUNT(*) FROM #{bank}.detalheorcamento D WHERE D.`CodigoOrcamento` = Q.`codigoorcamento`) AS itens, " \
      "(SELECT MIN(X.`CodigoOS`) FROM #{bank}.os X WHERE X.`Orcamento` = Q.`codigoorcamento`) AS os_ligada " \
      "FROM #{bank}.orcamento Q WHERE Q.`codigoorcamento` = #{S.int(@draft.quote_number)}"
  end

  # reserva com o aviso do próprio Mais Prático: só se estiver em NEGOCIAÇÃO, sem OS e ninguém com ele aberto (aviso de
  # mais de IN_USE_HOURS horas é sobra e não conta); a nossa reserva anterior vale de novo
  def reserve_quote_sql
    "UPDATE #{bank}.orcamento Q SET Q.`OrcamentoEmUtilizacao` = 1, Q.`CodUserEmUtilizacao` = #{S.int(@erp_user)}, " \
      "Q.`NomeUserEmUtilizacao` = #{S.str(@lock_name)}, Q.`DataEmUtilizacao` = NOW() " \
      "WHERE Q.`codigoorcamento` = #{S.int(@draft.quote_number)} AND Q.`Status` = #{S.str(NEGOTIATION)} AND IFNULL(Q.`OrdemServico`, 0) = 0 " \
      "AND (IFNULL(Q.`NomeUserEmUtilizacao`, '') = #{S.str(@lock_name)} OR NOT (IFNULL(Q.`OrcamentoEmUtilizacao`, 0) = 1 " \
      "AND IFNULL(Q.`DataEmUtilizacao` > NOW() - INTERVAL #{IN_USE_HOURS} HOUR, 0) = 1))"
  end

  # fecha o orçamento como a conversão do desktop: FECHADO, número da OS, quem converteu, dia do status; tira o aviso
  # de uso. Só se a reserva ainda for nossa e a OS for a deste rascunho.
  def close_quote_sql(number)
    "UPDATE #{bank}.orcamento Q SET Q.`Status` = #{S.str(CLOSED)}, Q.`OrdemServico` = #{S.int(number)}, " \
      "Q.`ConvertidoPor` = #{S.int(@erp_user)}, Q.`DataStatus` = CURDATE(), #{release_sets} " \
      "WHERE Q.`codigoorcamento` = #{S.int(@draft.quote_number)} AND #{reserved_guard} AND EXISTS (SELECT 1 FROM #{bank}.os O " \
      "WHERE #{own_order(number)} AND O.`Orcamento` = #{S.int(@draft.quote_number)})"
  end

  # tira o nosso aviso de uso (falhou antes de fechar): só se ainda for nosso
  def release_quote_sql
    "UPDATE #{bank}.orcamento Q SET #{release_sets} WHERE Q.`codigoorcamento` = #{S.int(@draft.quote_number)} " \
      "AND Q.`NomeUserEmUtilizacao` = #{S.str(@lock_name)}"
  end

  private

  # o que a Nova OS e a conversão gravam igual: situação, tipo, cliente, documento, técnico, máquina, datas pedidas,
  # usuário, classe, máquina normal/parada, marca e o envio para o app do técnico
  def common_header
    fields = @draft.fields
    machine = fields['maquina'].to_i.positive? ? S.int(fields['maquina']) : 'NULL'
    {
      'CodigoOS' => 'M.proximo', 'TipoAtendimento' => text('tipo_atendimento', 50), 'Situacao' => S.str(NEGOTIATION),
      'CodigoCliente' => 'C.`CodigoCliente`', 'CPF_CNPJ' => 'C.`CPF_CNPJ`', 'Tecnico' => positive('tecnico'),
      'Atendente' => S.int(@erp_user), 'IDLogado' => S.int(@erp_user), 'Hora' => "DATE_FORMAT(NOW(), '%H:%i')",
      'DataPrevisao' => datetime(fields['previsao']), 'DataEntrega' => datetime(fields['entrega']), 'Horimetro' => text('horimetro', 7),
      'CodigoMaquina' => machine, 'NSerie' => machine == 'NULL' ? 'NULL' : 'E.`NSerie`', 'ClasseOS' => positive('classe'),
      'IsCliente' => '1', 'StatusMaquina' => S.str(fields['maquina_parada'] == true ? 'PARADA' : 'NORMAL'),
      'CkListaMaqCliente' => fields['maquina_do_cliente'] == false ? '0' : '1', 'CodigoPedidoOutroSistema' => marker
    }.merge(app_header)
  end

  # "Enviar para o app do técnico": os campos que fazem a OS aparecer no celular, como nas OS enviadas pelo desktop
  def app_header
    return {} unless @draft.fields['enviar_app'] == true

    { 'ExibirFSMMobile' => '1', 'SubStatusFSM' => S.str(APP_SUBSTATUS) }
  end

  def insert_header(values, from)
    "INSERT INTO #{bank}.os (#{values.keys.map { |column| S.column(column) }.join(', ')}) SELECT #{values.values.join(', ')} #{from} " \
      "AND NOT EXISTS (SELECT 1 FROM #{bank}.os X WHERE X.`CodigoPedidoOutroSistema` = #{marker})"
  end

  def number_join = "JOIN (#{number_sql} FROM #{bank}.os) M"

  def machine_join
    machine = @draft.fields['maquina'].to_i
    machine.positive? ? "LEFT JOIN #{bank}.equipamentos E ON E.`Seq` = #{S.int(machine)}" : ''
  end

  def reserved_guard
    "Q.`Status` = #{S.str(NEGOTIATION)} AND IFNULL(Q.`OrdemServico`, 0) = 0 AND Q.`NomeUserEmUtilizacao` = #{S.str(@lock_name)}"
  end

  def release_sets
    'Q.`OrcamentoEmUtilizacao` = 0, Q.`CodUserEmUtilizacao` = NULL, Q.`NomeUserEmUtilizacao` = NULL, Q.`DataEmUtilizacao` = NULL'
  end

  def quote_order_link = 'Q.`Pedido` AS pedido'

  def own_order(number) = "O.`CodigoOS` = #{S.int(number)} AND O.`CodigoPedidoOutroSistema` = #{marker}"

  def free_line(number, position)
    "NOT EXISTS (SELECT 1 FROM #{bank}.detalheos X WHERE X.`CodigoOS` = #{S.int(number)} AND X.`CodigoItem` = #{S.int(position)})"
  end

  # linha nova da conversão: venda externa e custo médio só de peça
  def add_item_extras(targets, values, os_set)
    if os_set.include?('customedio')
      targets += ['custoMedio']
      values += ['CASE WHEN IFNULL(P.`Tipo`, 0) = 1 THEN NULL ELSE D.`custoMedio` END']
    end
    if os_set.include?('ckvendaexterna')
      targets += ['ckVendaExterna']
      values += ['1']
    end
    [targets, values]
  end

  def text(key, limit) = S.str(@draft.fields[key].to_s.strip.first(limit).presence)

  def positive(key)
    value = @draft.fields[key].to_i
    value.positive? ? S.int(value) : 'NULL'
  end

  # 'AAAA-MM-DD HH:MM:SS' a partir do que a tela mandou (dia ou dia e hora); vazio vira NULL
  def datetime(value)
    text = value.to_s.strip
    return 'NULL' if text.empty?

    parsed = text.include?('T') || text.include?(' ') ? Time.zone.parse(text) : Date.parse(text)
    S.str(parsed.strftime(text.length > 10 ? '%Y-%m-%d %H:%M:00' : '%Y-%m-%d 00:00:00'))
  rescue ArgumentError, TypeError
    'NULL'
  end
end
