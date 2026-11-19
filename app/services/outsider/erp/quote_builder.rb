# OUTSIDER: monta as chamadas SQL que gravam no ERP um orçamento de peças e serviços feito no chat
# (Outsider::Erp::Budget). Usa as PRÓPRIAS funções do Mais Prático (sp_CadastraOrcamento, sp_CadastraItemOrcamento,
# sp_FinalizaOrcamento), que cuidam de numeração, impostos e totais. Puro: não executa nada (quem roda é o
# Outsider::Erp::QuoteCreator, via Client#query_execute). Toda unidade tem sua cópia das funções, então o banco vai como
# prefixo (somosemp.sp_...): a gravação nunca sai da unidade. Todo valor passa pelo Outsider::Erp::Sql.
#
# Idempotência: CodigoIntegracaoMobile = Budget#mobile_key; reexecutar o cabeçalho devolve o mesmo orçamento. As escritas
# fora das funções (Demais Condições, linha de serviço) levam esse código no WHERE: só tocam o orçamento que o chat criou.
class Outsider::Erp::QuoteBuilder
  S = Outsider::Erp::Sql
  # coluna do orçamento no ERP (Demais Condições, varchar) <= condição do rascunho (Outsider::Erp::BudgetForm::TERMS)
  CONDITIONS = {
    'PrazoEntrega' => 'prazo_entrega', 'Validade' => 'validade', 'PrazoGarantia' => 'garantia', 'Reajuste' => 'reajuste',
    'ICMS' => 'icms', 'IPI' => 'ipi', 'descFrete' => 'desc_frete', 'TaxaArmazenagem' => 'armazenagem', 'TaxaCancelamento' => 'cancelamento'
  }.freeze

  # service_codes: serviços gravados direto (entram no total de serviços do orçamento)
  def initialize(budget, document:, seller:, service_codes: [])
    @budget = budget
    @document = document
    @seller = seller
    @service_codes = service_codes
  end

  def company = @budget.company
  def bank = S.ident(@budget.company)
  def key = S.str(@budget.mobile_key)

  # SELECT <banco>.sp_CadastraOrcamento(...) -> devolve o CodigoOrcamento
  def header_sql
    "SELECT #{bank}.sp_CadastraOrcamento(#{header_args.join(', ')}) AS codigo"
  end

  # peça: pela função do ERP, que calcula os impostos pela NCM do produto e UF do cliente
  def item_sql(number, item)
    args = [S.int(number), S.int(item['codigo']), S.dec(item['quantidade']), S.dec(item['preco']), S.dec(item['desconto']),
            S.dec(Outsider::Erp::Budget.line_total(item)), key]
    "SELECT #{bank}.sp_CadastraItemOrcamento(#{args.join(', ')}) AS codigo"
  end

  # serviço: a função do ERP descarta item sem NCM (LEFT JOIN filtrado no WHERE), e serviço não tem NCM. Grava a linha
  # com as mesmas colunas e contas da função, sem imposto, só se o produto for serviço (Tipo = 1) e o orçamento for o
  # deste rascunho. O próximo CodigoItem sai de uma tabela derivada (o MySQL não deixa subconsulta na própria tabela).
  def service_sql(number, item)
    quantity = S.dec(item['quantidade'])
    price = S.dec(item['preco'])
    total = S.dec(Outsider::Erp::Budget.line_total(item))
    "INSERT INTO #{bank}.detalheorcamento (CodigoOrcamento, CodigoItem, CodigoProduto, Quantidade, PrecoUnitario, Desconto, " \
      'PercDesconto, TotalLinha, ClasFiscal, VrTotalTributosLinha) ' \
      "SELECT O.codigoorcamento, M.proximo, P.CodigoProduto, #{quantity}, #{price}, ((#{price} * #{quantity}) - #{total}) / #{quantity}, " \
      "#{S.dec(item['desconto'])}, #{total}, P.ClasFiscal, 0 " \
      "FROM #{bank}.orcamento O JOIN #{bank}.produtos P ON P.CodigoProduto = #{S.int(item['codigo'])} AND P.Tipo = 1 " \
      "JOIN (SELECT IFNULL(MAX(CodigoItem), 0) + 1 AS proximo FROM #{bank}.detalheorcamento WHERE CodigoOrcamento = #{S.int(number)}) M " \
      "WHERE O.codigoorcamento = #{S.int(number)} AND O.CodigoIntegracaoMobile = #{key}"
  end

  def finalize_sql(number)
    "SELECT #{bank}.sp_FinalizaOrcamento(#{S.int(number)}) AS resultado"
  end

  # Demais Condições (texto) que existem nesta unidade e foram preenchidas; nil quando não há o que gravar
  def conditions_sql(number, columns)
    existing = columns.to_set(&:downcase)
    sets = CONDITIONS.filter_map do |column, term|
      value = @budget.terms[term].to_s.strip
      "O.#{S.column(column)} = #{S.str(value)}" if value.present? && existing.include?(column.downcase)
    end
    sets << "O.`totalServicos` = #{S.dec(services_total)}" if services_total.positive? && existing.include?('totalservicos')
    sets.concat(authorization_sets(existing))
    return if sets.empty?

    "UPDATE #{bank}.orcamento O SET #{sets.join(', ')} WHERE O.codigoorcamento = #{S.int(number)} AND O.CodigoIntegracaoMobile = #{key}"
  end

  # desconto liberado no chat: quem liberou (código de funcionário do ERP) e quando, nos campos que o ERP já tem
  def authorization_sets(existing)
    code = @budget.approval.to_h['by_code'].to_i
    return [] unless code.positive? && existing.include?('autorizadopor')

    sets = ["O.`AutorizadoPor` = #{S.int(code)}"]
    sets << 'O.`DataAutorizadoPor` = NOW()' if existing.include?('dataautorizadopor')
    sets
  end

  # linhas já gravadas no orçamento (código do produto, na ordem): para retomar sem duplicar e para achar o que o ERP
  # deixou de fora
  def lines_sql(number)
    "SELECT CodigoItem, CodigoProduto FROM #{bank}.detalheorcamento WHERE CodigoOrcamento = #{S.int(number)} ORDER BY CodigoItem"
  end

  def customer_sql
    "SELECT C.CodigoCliente AS codigo, C.CPF_CNPJ AS documento, C.UF AS uf FROM #{bank}.clientes C " \
      "WHERE C.CodigoCliente = #{S.int(@budget.customer_code)}"
  end

  private

  # na ordem da função: cliente, CPF/CNPJ, forma de pagamento, frete, contato, desconto (0: vai por linha), observação,
  # vendedor, transportadora (0: nenhuma), tipo de frete, gênero da operação, pedido do cliente, código de integração, data
  def header_args
    terms = @budget.terms
    [S.int(@budget.customer_code), S.str(@document.to_s.first(14)), S.int(terms['forma_pagto']), S.dec(terms['frete_valor']),
     text(terms, 'contato', 50), '0', text(terms, 'observacoes', 2000), S.int(@seller), '0',
     S.int(terms['tipo_frete'].to_i), S.int(terms['genero'].to_i), text(terms, 'pedido_cliente', 20), key, S.date(Time.zone.today)]
  end

  def text(terms, key, limit) = S.str(terms[key].to_s.first(limit))

  # serviços gravados direto (a função de finalizar não preenche o total de serviços)
  def services_total
    @services_total ||= @budget.items.select { |item| Array(@service_codes).include?(item['codigo'].to_i) }
                               .sum { |item| Outsider::Erp::Budget.line_total(item) }
  end
end
