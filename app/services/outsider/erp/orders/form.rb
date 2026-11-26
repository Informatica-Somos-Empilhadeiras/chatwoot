# OUTSIDER: aplica o que veio da tela num rascunho de OS (Outsider::Erp::OrderDraft). Responsabilidade única: limpar e
# limitar cada campo no tamanho das colunas da OS do Mais Prático (o navegador manda o que quiser). Só rascunho muda;
# rascunho que já tem número no ERP (gravação parou no meio) não muda: o certo é gravar de novo, que continua.
# Na conversão o cliente e os itens são os do orçamento: só os campos da OS mudam.
class Outsider::Erp::Orders::Form
  class Invalid < StandardError; end

  # campo => limite (texto), :int, :bool, :datetime (AAAA-MM-DDTHH:MM) ou :date (AAAA-MM-DD). Tamanhos: os, 25/11/2026
  FIELDS = {
    'tipo_atendimento' => 50, 'maquina' => :int, 'maquina_descricao' => 150, 'serie' => 50,
    'horimetro' => 7, 'previsao' => :datetime, 'entrega' => :date, 'classe' => :int, 'maquina_parada' => :bool,
    'maquina_do_cliente' => :bool, 'defeitos' => 5000, 'observacoes' => 5000, 'agendar' => :bool
  }.freeze
  # técnico e "Enviar para o app do técnico" saíram da OS feita no chat: ficam no Agendar (Outsider::Erp::OrderScheduler)
  ITEM_FIELDS = %w[codigo descricao unidade tipo quantidade preco].freeze
  MAX_ITEMS = 100
  MAX_VALUE = 100_000_000
  DATETIME = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}\z/
  DATE = /\A\d{4}-\d{2}-\d{2}\z/

  def initialize(draft, settings)
    @draft = draft
    @settings = settings
  end

  def apply(params)
    raise Invalid, 'not_draft' unless @draft.draft?
    raise Invalid, 'in_erp' if @draft.in_erp?

    params = params.to_h.deep_stringify_keys
    apply_customer(params) if params.key?('customer_code') && @draft.fresh?
    @draft.fields = @draft.fields.merge(clean_fields(params['fields'].to_h)) if params.key?('fields')
    @draft.items = clean_items(params['items']) if params.key?('items') && @draft.fresh?
    @draft.save!
    @draft
  end

  private

  # cliente do ERP: a unidade precisa estar liberada para OS pelo chat; trocar de cliente tira a máquina escolhida
  def apply_customer(params)
    company = params['company'].to_s.presence || @draft.company
    raise Invalid, 'company' unless @settings.order_company?(company)

    code = Integer(params['customer_code'].to_s, exception: false)
    changed = code != @draft.customer_code || company != @draft.company
    @draft.company = company
    @draft.customer_code = code&.positive? ? code : nil
    @draft.customer_name = params['customer_name'].to_s.squish.first(150).presence
    @draft.fields = @draft.fields.except('maquina', 'maquina_descricao', 'serie', 'horimetro', 'maquina_do_cliente') if changed
  end

  def clean_fields(raw)
    raw.slice(*FIELDS.keys).to_h { |key, value| [key, clean(FIELDS[key], value)] }
  end

  def clean(kind, value)
    case kind
    when :int then Integer(value.to_s, exception: false)&.then { |number| number.positive? ? number : nil }
    when :bool then ActiveModel::Type::Boolean.new.cast(value) == true
    when :datetime then value.to_s.strip.then { |text| text.match?(DATETIME) ? text : nil }
    when :date then value.to_s.strip.first(10).then { |text| text.match?(DATE) ? text : nil }
    else value.to_s.strip.first(kind).presence
    end
  end

  # peças e serviços: código do ERP, quantidade e preço positivos (o desconto fica para o escritório, como no app)
  def clean_items(list)
    items = Array(list).first(MAX_ITEMS + 1)
    raise Invalid, 'too_many_items' if items.size > MAX_ITEMS

    items.filter_map { |item| clean_item(item.to_h.stringify_keys) }
  end

  def clean_item(item)
    code = Integer(item['codigo'].to_s, exception: false)
    return unless code&.positive?

    quantity = decimal(item['quantidade'])
    price = decimal(item['preco'])
    raise Invalid, 'item' unless quantity.positive? && quantity <= MAX_VALUE && price >= 0 && price <= MAX_VALUE

    { 'codigo' => code, 'descricao' => item['descricao'].to_s.squish.first(150), 'unidade' => item['unidade'].to_s.squish.first(6),
      'tipo' => item['tipo'].to_i == 1 ? 1 : 0, 'quantidade' => quantity.round(4).to_s('F'), 'preco' => price.round(4).to_s('F') }
  end

  def decimal(value)
    BigDecimal(value.to_s.tr(',', '.'))
  rescue ArgumentError, TypeError
    BigDecimal(0)
  end
end
