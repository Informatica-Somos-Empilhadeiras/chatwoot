# OUTSIDER: o relatório de um rascunho de orçamento (ainda não gravado no ERP), no mesmo formato do
# Outsider::Erp::QuoteReport, para o "Ver PDF" antes de gravar. Sem número e sem impostos (quem calcula é o ERP ao
# gravar): o PDF sai marcado como prévia. Emitente e cliente vêm do ERP quando dá; se o ERP não responder, sai com o
# que o rascunho tem.
class Outsider::Erp::BudgetPreview
  def initialize(budget)
    @budget = budget
    @account = budget.account
    @client = Outsider::Erp::Client.new(Outsider::Erp::Settings.new(@account))
  end

  def build
    terms = @budget.terms
    lines = @budget.items.map { |item| line(item) }
    {
      'numero' => nil, 'data' => Time.zone.today.iso8601, 'company' => @budget.company, 'previa' => true,
      'emitente' => emitter, 'cliente' => customer.merge('contato' => terms['contato']), 'itens' => lines,
      'pagamento' => payment_name(terms['forma_pagto']), 'observacoes' => terms['observacoes'].to_s, 'vendedor' => seller(terms['vendedor'])
    }.merge(money(lines, terms))
  end

  private

  def line(item)
    gross = item['quantidade'].to_f * item['preco'].to_f
    {
      'codigo' => item['codigo'], 'descricao' => item['descricao'], 'unidade' => item['unidade'], 'quantidade' => item['quantidade'].to_f,
      'ncm' => item['ncm'], 'cst' => nil, 'icms' => nil, 'vr_icms' => nil, 'desconto' => (gross * item['desconto'].to_f / 100).round(2),
      'unitario' => item['preco'].to_f, 'total' => Outsider::Erp::Budget.line_total(item).to_f
    }
  end

  def money(lines, terms)
    {
      'condicoes' => conditions(terms), 'totais' => totals(lines, terms),
      'total' => (lines.sum { |row| row['total'] } + terms['frete_valor'].to_f).round(2)
    }
  end

  def conditions(terms)
    Outsider::Erp::QuoteReport::CONDITIONS.map { |label, key| [label, terms[Outsider::Erp::Budget::REPORT_TERMS.fetch(key, key)].to_s] }
  end

  def totals(lines, terms)
    [['Sub-Total', lines.sum { |row| row['total'] }.round(2)], ['Frete', terms['frete_valor'].to_f.round(2)]]
  end

  def emitter
    Outsider::Erp::Emitter.new(@account, client: @client).data_for(@budget.company)
  end

  def customer
    record = Outsider::Erp::CustomerRecord.new(@account, client: @client).find(@budget.company, @budget.customer_code)
    record.presence || { 'codigo' => @budget.customer_code, 'nome' => @budget.customer_name }
  rescue Outsider::Erp::Client::Error
    { 'codigo' => @budget.customer_code, 'nome' => @budget.customer_name }
  end

  def payment_name(code)
    return '' unless code.to_i.positive?

    Outsider::Erp::PaymentTerms.new(@account).list.find { |row| row[:codigo] == code.to_i }&.dig(:descricao).to_s
  rescue Outsider::Erp::Client::Error
    ''
  end

  def seller(code)
    Outsider::Erp::SellerName.new(@account, client: @client).for_code(@budget.company, code) || @budget.user&.name
  rescue Outsider::Erp::Client::Error
    @budget.user&.name
  end
end
