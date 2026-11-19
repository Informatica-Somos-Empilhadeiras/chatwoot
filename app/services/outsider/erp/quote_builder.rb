# OUTSIDER: monta as chamadas SQL que criam um orçamento no ERP a partir de uma proposta do CRM, usando as PRÓPRIAS
# funções do Mais Prático (sp_CadastraOrcamento, sp_CadastraItemOrcamento, sp_FinalizaOrcamento) — que já cuidam de
# numeração, impostos e totais. Puro: não executa nada (quem roda é o Client, via Outsider::Erp::QuoteCreator). Toda
# unidade tem sua cópia das funções, então o banco vai como prefixo (somosemp.sp_...): a gravação nunca sai da unidade.
#
# Idempotência: o CodigoIntegracaoMobile = "CW-<id da proposta>"; reexecutar devolve o mesmo orçamento, não duplica.
class Outsider::Erp::QuoteBuilder
  S = Outsider::Erp::Sql
  PREFIX = 'CW-'.freeze

  # dados já resolvidos pelo QuoteCreator (empresa/banco, código do cliente no ERP, id do vendedor no ERP)
  def initialize(proposal:, settings:, company:, codigo_cliente:, vendedor_erp_id:)
    @proposal = proposal
    @settings = settings
    @company = company
    @codigo_cliente = codigo_cliente
    @vendedor = vendedor_erp_id
  end

  attr_reader :company

  def mobile_key = "#{PREFIX}#{@proposal.id}"

  # itens que entram no orçamento (têm produto do ERP vinculado) e os que ficam de fora (livres)
  def sellable_items = @proposal.items.select { |item| erp_code(item).present? }
  def skipped_items  = @proposal.items.reject { |item| erp_code(item).present? }

  # CodigoProduto do ERP vinculado ao produto do item (nil = item livre); público para o QuoteCreator conferir
  def erp_code(item) = item.product&.erp_codigo_produto

  # SELECT <banco>.sp_CadastraOrcamento(...) -> devolve o CodigoOrcamento
  def header_sql
    "SELECT #{fn('sp_CadastraOrcamento')}(#{header_args.join(', ')}) AS codigo"
  end

  def item_sql(codigo_orcamento, item)
    args = [
      S.int(codigo_orcamento), S.int(erp_code(item)), S.dec(item.quantity), S.dec(reais(item.unit_price_cents)),
      S.dec(desconto_perc(item)), S.dec(reais(item.total_cents)), S.str(mobile_key)
    ]
    "SELECT #{fn('sp_CadastraItemOrcamento')}(#{args.join(', ')}) AS codigo"
  end

  def finalize_sql(codigo_orcamento)
    "SELECT #{fn('sp_FinalizaOrcamento')}(#{S.int(codigo_orcamento)}) AS resultado"
  end

  private

  # na ordem da função: cliente, CPF/CNPJ, forma de pagamento, frete, contato, desconto, observação, vendedor,
  # transportadora, tipo de frete, gênero da operação, pedido do cliente, código de integração, data
  def header_args
    [S.int(@codigo_cliente), S.str(document)] + terms_args +
      [S.str(pedido_cliente), S.str(mobile_key), S.date(@proposal.issued_on)]
  end

  def terms_args
    data = @settings.data
    [S.int(data['quote_forma_pagto']), S.dec(0), S.str(contato), S.dec(0), S.str(@proposal.notes), S.int(@vendedor), S.int(0),
     S.int(data['quote_tipo_frete']), S.int(data['quote_genero_operacao'])]
  end

  def fn(name) = "#{S.ident(@company)}.#{name}"
  def reais(cents) = cents.to_i / 100.0
  def document = @proposal.customer.to_h['document']
  def contato = @proposal.customer.to_h['attention'].presence || @proposal.contact&.name
  def pedido_cliente = @proposal.customer.to_h['purchase_order']

  # % de desconto do item (a função guarda em PercDesconto; o R$ ela recalcula pelo total)
  def desconto_perc(item)
    gross = item.gross_cents.to_i
    return 0 if gross <= 0

    (item.discount_cents.to_i * 100.0 / gross).round(2)
  end
end
