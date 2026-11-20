# OUTSIDER: o "Copiar" de um orçamento de peças e serviços: cliente, itens e condições no formato do rascunho (vai para o
# Outsider::Erp::BudgetDefaults, que passa tudo pelo Outsider::Erp::BudgetForm). Feito no chat: o que está guardado.
# Feito no Mais Prático (registro "imported", sem itens aqui): lê o cabeçalho e as linhas do ERP
# (Outsider::Erp::QuoteReport), com o tipo de cada produto (peça ou serviço) e o desconto da linha em %.
class Outsider::Erp::BudgetCopy
  # campos do cabeçalho do ERP que viram condição do rascunho (Demais Condições e observações)
  HEADER_TERMS = %w[prazo_entrega validade garantia reajuste icms_txt ipi_txt desc_frete armazenagem cancelamento observacoes].freeze

  def initialize(account)
    @account = account
  end

  def from(budget)
    base = { 'empresa' => budget.company, 'codigo' => budget.customer_code, 'nome' => budget.customer_name }
    return base.merge('terms' => budget.terms, 'items' => budget.items) if budget.items.any? || !budget.in_erp?

    base.merge(from_erp(budget.company, budget.erp_number))
  end

  # itens e condições como estão agora no ERP (também para abrir a edição de um orçamento gravado)
  def current(company, number) = from_erp(company, number)

  private

  def from_erp(company, number)
    report = Outsider::Erp::QuoteReport.new(@account)
    { 'terms' => terms(report.header(company, number)), 'items' => items(company, report.lines(company, number)) }
  end

  def terms(header)
    list = HEADER_TERMS.to_h { |key| [Outsider::Erp::Budget::REPORT_TERMS.fetch(key, key), header[key].to_s.strip] }.compact_blank
    code = payment_code(header['pagamento'].to_s.squish)
    code ? list.merge('forma_pagto' => code) : list
  end

  # o ERP guarda o nome da forma de pagamento no orçamento; o rascunho guarda o código
  def payment_code(name)
    return if name.blank?

    Outsider::Erp::PaymentTerms.new(@account).list.find { |row| row[:descricao].split(' / ').include?(name) }&.dig(:codigo)
  rescue Outsider::Erp::Client::Error
    nil
  end

  def items(company, lines)
    kinds = Outsider::Erp::Catalog.new(@account).kinds(company, lines.pluck('codigo'))
    lines.map do |line|
      gross = line['quantidade'].to_f * line['unitario'].to_f
      {
        'codigo' => line['codigo'], 'descricao' => line['descricao'], 'unidade' => line['unidade'], 'ncm' => line['ncm'],
        'tipo' => kinds[line['codigo'].to_i] == 1 ? 1 : 0, 'quantidade' => line['quantidade'], 'preco' => line['unitario'],
        'desconto' => gross.positive? ? (line['desconto'].to_f / gross * 100).round(2) : 0
      }
    end
  end
end
