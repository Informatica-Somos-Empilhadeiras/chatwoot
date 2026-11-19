# OUTSIDER: cria no ERP o orçamento de uma proposta do CRM. Orquestra (não monta SQL nem fala HTTP direto): resolve o
# cliente e o vendedor, pede as chamadas ao Outsider::Erp::QuoteBuilder e roda pelo Outsider::Erp::Client#query_execute,
# na ordem cabeçalho -> itens -> finaliza. Guarda o número do orçamento na proposta.
#
# Gates: só com a escrita de orçamento ligada nas Configurações (quote_write_enabled, desligada por padrão) e com a
# forma de pagamento padrão definida. Idempotente: se a proposta já tem orçamento, devolve o existente; e os itens só
# entram se o orçamento ainda não tiver nenhum (evita duplicar numa reexecução).
class Outsider::Erp::QuoteCreator
  class Disabled < StandardError; end
  class Invalid < StandardError; end

  Result = Struct.new(:number, :company, :skipped, :already, keyword_init: true)

  def initialize(account:, user:, proposal:, company: nil)
    @account = account
    @user = user
    @proposal = proposal
    @company = company.presence
    @settings = Outsider::Erp::Settings.new(account)
    @client = Outsider::Erp::Client.new(@settings)
    @catalog = Outsider::Erp::Catalog.new(account)
  end

  def call
    ensure_ready!
    link = resolve_link
    return existing(link) if @proposal.erp_quote_number.present?

    builder = build(link)
    # dos itens com produto do ERP, só entram os cujo CodigoProduto existe mesmo na unidade (a função do ERP
    # ignora código inexistente em silêncio, o que baixaria o total). Os ausentes viram "deixados de fora".
    present, absent = partition(link['empresa'], builder)
    raise Invalid, 'sem_itens' if present.empty?

    number = create(builder, present)
    persist(number, link['empresa'])
    Result.new(number: number, company: link['empresa'], skipped: labels(builder.skipped_items + absent), already: false)
  end

  private

  def ensure_ready!
    raise Disabled unless @settings.quote_write_enabled?
    raise Invalid, 'forma_pagto' if @settings.data['quote_forma_pagto'].to_i <= 0
  end

  # cliente do ERP ligado ao contato: o da unidade pedida, senão o único; clientes em mais de uma unidade sem a
  # unidade escolhida => ambíguo (a tela pergunta). Dois códigos na mesma unidade: vale o primeiro vínculo.
  def resolve_link
    links = Outsider::Erp::ContactLink.new(@proposal.contact).links
    raise Invalid, 'sem_cliente' if links.empty?

    scoped = scoped_links(links)
    companies = scoped.pluck('empresa').uniq
    raise Invalid, "ambiguo:#{companies.join(',')}" if companies.size > 1

    scoped.first
  end

  def scoped_links(links)
    return links unless @company

    links.select { |link| link['empresa'] == @company }.presence || raise(Invalid, 'empresa_invalida')
  end

  def build(link)
    Outsider::Erp::QuoteBuilder.new(
      proposal: @proposal, settings: @settings, company: link['empresa'],
      codigo_cliente: link['codigo'], vendedor_erp_id: vendedor_id
    )
  end

  # separa os itens vendáveis em presentes/ausentes na unidade; se a conferência falhar, segue com todos
  def partition(company, builder)
    codes = @catalog.existing_codes(company, builder.sellable_items.map { |item| builder.erp_code(item) })
    builder.sellable_items.partition { |item| codes.include?(builder.erp_code(item).to_i) }
  rescue Outsider::Erp::Client::Error
    [builder.sellable_items, []]
  end

  def create(builder, items)
    number = Integer(scalar(@client.query_execute(builder.header_sql)))
    raise Invalid, 'sem_numero' if number <= 0

    items.each { |item| @client.query_execute(builder.item_sql(number, item)) } if items_count(builder.company, number).zero?
    @client.query_execute(builder.finalize_sql(number))
    number
  end

  # nº do orçamento quando a proposta já foi sincronizada (não regrava, não duplica itens)
  def existing(link)
    Result.new(number: @proposal.erp_quote_number, company: @proposal.erp_company || link['empresa'], skipped: [], already: true)
  end

  def items_count(company, number)
    sql = "SELECT COUNT(*) AS n FROM #{Outsider::Erp::Sql.ident(company)}.detalheorcamento " \
          "WHERE CodigoOrcamento = #{Outsider::Erp::Sql.int(number)}"
    scalar(@client.query_execute(sql)).to_i
  rescue Outsider::Erp::Client::Error
    0
  end

  def persist(number, company)
    @proposal.update_columns(erp_company: company, erp_quote_number: number, erp_synced_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    Rails.logger.info("[Outsider::Erp] conta #{@account.id} usuário #{@user.id} proposta #{@proposal.id} => orçamento #{company}/#{number}")
  end

  # primeira coluna da primeira linha devolvida pelo query_execute (as funções voltam [{ "codigo" => N }])
  def scalar(rows)
    row = rows.is_a?(Array) ? rows.first : rows
    row.is_a?(Hash) ? row.values.first : row
  end

  def vendedor_id
    owner = @proposal.owner || @proposal.created_by || @user
    @settings.erp_user_id_for(owner)
  end

  def labels(items)
    items.map { |item| item.description.to_s.truncate(60) }
  end
end
