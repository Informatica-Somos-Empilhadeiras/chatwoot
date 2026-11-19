# OUTSIDER: aplica o que veio da tela num rascunho de orçamento (Outsider::Erp::Budget). Responsabilidade única: limpar
# e limitar cada campo (o navegador manda o que quiser) no tamanho que o ERP aceita. Só rascunho muda: depois de
# gravado no ERP o orçamento é do Mais Prático (para mudar, "Copiar" abre um rascunho novo).
class Outsider::Erp::BudgetForm
  class Invalid < StandardError; end

  # condição => tamanho máximo (texto) ou :int / :dec. Os limites são os das colunas/parâmetros do ERP
  # (sp_CadastraOrcamento: contato 50, pedido 20, observação 2000; Demais Condições: varchar 255, descFrete 150).
  TERMS = {
    'forma_pagto' => :int, 'genero' => :int, 'tipo_frete' => :int, 'vendedor' => :int, 'frete_valor' => :dec,
    'contato' => 50, 'pedido_cliente' => 20, 'observacoes' => 2000, 'prazo_entrega' => 255, 'validade' => 255,
    'garantia' => 255, 'reajuste' => 255, 'icms' => 255, 'ipi' => 255, 'desc_frete' => 150, 'armazenagem' => 255,
    'cancelamento' => 255
  }.freeze
  # gênero da operação (TipoNCM do ERP: decide a NCM/impostos de cada peça), como no cadastro do Mais Prático
  GENEROS = [
    [0, 'VENDA CONSUMO'], [1, 'REVENDA'], [4, 'CONSIGNAÇÃO'], [5, 'DEMONSTRAÇÃO'], [6, 'AMOSTRA'], [7, 'TROCA'], [8, 'DOAÇÃO'],
    [9, 'REMESSA'], [10, 'OUTRAS SAÍDAS'], [12, 'VENDA DE CONSIGNAÇÃO'], [13, 'EMPRESTIMO']
  ].map { |code, name| { codigo: code, descricao: name } }.freeze
  # tipo de frete (TipoFrete do orçamento, um dígito), como o modFrete da NF-e; no banco da Somos aparecem 0 (quase
  # todos, ex.: orçamento 3309 "EMITENTE"), 9, 3 e 1
  FRETES = [[0, 'Emitente (CIF)'], [1, 'Destinatário (FOB)'], [2, 'Terceiros'], [3, 'Próprio do emitente'],
            [4, 'Próprio do destinatário'], [9, 'Sem frete']].map { |code, name| { codigo: code, descricao: name } }.freeze
  MAX_ITEMS = 150
  MAX_VALUE = 1_000_000_000

  def initialize(budget, settings)
    @budget = budget
    @settings = settings
  end

  def apply(params)
    raise Invalid, 'not_draft' unless @budget.draft?
    # a gravação parou no meio e o orçamento já tem número no ERP: muda nada, só gravar de novo (continua de onde parou)
    raise Invalid, 'in_erp' if @budget.in_erp?

    params = params.to_h.deep_stringify_keys
    apply_customer(params) if params.key?('customer_code')
    @budget.terms = @budget.terms.merge(clean_terms(params['terms'].to_h)) if params.key?('terms')
    @budget.items = clean_items(params['items']) if params.key?('items')
    @budget.save!
    @budget
  end

  private

  # cliente do ERP: a unidade precisa estar nas Configurações (a gravação acontece no banco dela)
  def apply_customer(params)
    company = params['company'].to_s
    raise Invalid, 'company' unless @settings.companies.include?(company)

    code = Integer(params['customer_code'].to_s, exception: false)
    raise Invalid, 'customer' unless code&.positive?

    # código de produto é de cada unidade: trocar de unidade com itens já escolhidos misturaria cadastros
    raise Invalid, 'company_items' if company != @budget.company && @budget.items.any? && !params.key?('items')

    @budget.assign_attributes(company: company, customer_code: code, customer_name: params['customer_name'].to_s.squish.first(120))
  end

  def clean_terms(terms)
    terms.slice(*TERMS.keys).to_h do |key, value|
      kind = TERMS[key]
      [key, clean_value(kind, value)]
    end
  end

  def clean_value(kind, value)
    case kind
    when :int then Integer(value.to_s, exception: false)&.clamp(0, 999_999_999)
    when :dec then decimal(value, 0, MAX_VALUE).to_f
    else value.to_s.strip.first(kind)
    end
  end

  def clean_items(list)
    list = Array(list).first(MAX_ITEMS + 1)
    raise Invalid, 'too_many_items' if list.size > MAX_ITEMS

    list.filter_map { |item| clean_item(item.to_h.stringify_keys) }
  end

  def clean_item(item)
    code = Integer(item['codigo'].to_s, exception: false)
    return unless code&.positive?

    {
      'codigo' => code, 'descricao' => item['descricao'].to_s.squish.first(120), 'unidade' => item['unidade'].to_s.strip.first(22),
      'tipo' => item['tipo'].to_i == 1 ? 1 : 0, 'ncm' => item['ncm'].to_s.strip.first(10)
    }.merge(item_numbers(item))
  end

  def item_numbers(item)
    {
      'quantidade' => decimal(item['quantidade'], 0.0001, 1_000_000, default: 1).to_f,
      'preco' => decimal(item['preco'], 0, MAX_VALUE).round(2).to_f, 'desconto' => decimal(item['desconto'], 0, 100).round(2).to_f
    }
  end

  # aceita 1.234,56 / 1234.56 / número; fora da faixa fica no limite
  def decimal(value, min, max, default: 0)
    text = value.to_s.strip
    text = text.delete('.').tr(',', '.') if text.include?(',')
    number = BigDecimal(text.presence || default.to_s)
    number.clamp(BigDecimal(min.to_s), BigDecimal(max.to_s))
  rescue ArgumentError, TypeError
    BigDecimal(default.to_s)
  end
end
