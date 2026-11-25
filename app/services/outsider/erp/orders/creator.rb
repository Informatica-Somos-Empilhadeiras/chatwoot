# OUTSIDER: grava no ERP a OS de um rascunho do chat (Outsider::Erp::OrderDraft): a Nova OS e a conversão de um
# orçamento em OS. Orquestra (a SQL sai do Outsider::Erp::Orders::Sql, a conferência do Outsider::Erp::Orders::Checks):
#
#   conferência -> [conversão: reserva o orçamento] -> cabeçalho (número = maior + 1, com a marca do rascunho) ->
#   histórico (2 linhas, como o desktop) -> peças e serviços -> [conversão: somas dos impostos e fecha o orçamento] ->
#   [opcional: sub status Agendar atendimento pela rota oficial] -> leitura de volta
#
# Gates: Nova OS e conversão ligadas nas Configurações (desligadas por padrão), unidade liberada (order_companies) e o
# código de funcionário do ERP da pessoa nas Configurações (o histórico, o atendente e "convertido por" levam esse código).
# Retomável: se o ERP cair no meio, rodar de novo acha a OS pela marca e só faz o que falta (cada passo é idempotente).
# Falhou antes de fechar o orçamento: o aviso de uso que pusemos nele sai. Nada é apagado no ERP.
class Outsider::Erp::Orders::Creator
  class Disabled < StandardError; end
  class Invalid < StandardError; end

  LOCK_SECONDS = 240
  UNIT_WAIT = 15
  HEADER_TRIES = 3
  AGENDAR = /AGENDAR\s+ATENDIMENTO/i

  def initialize(draft, user:)
    @draft = draft
    @user = user
    @settings = Outsider::Erp::Settings.new(draft.account)
    @client = Outsider::Erp::Client.new(@settings)
    @schema = Outsider::Erp::Schema.new(draft.account, client: @client)
  end

  def call
    ensure_ready!
    return @draft if @draft.created?

    with_lock("order_draft:#{@draft.id}", wait: 0) do
      with_lock("order_unit:#{@draft.company}", wait: UNIT_WAIT) { run }
    end
  end

  private

  def run
    order = find_order || start_order
    number = order['numero'].to_i
    remember(number, order)
    history(number)
    lines(number)
    finish_conversion(number) if @draft.conversion?
    schedule(number) if @draft.fields['agendar'] == true
    finish(number)
  rescue StandardError
    release_quote
    raise
  end

  def ensure_ready!
    raise Disabled unless @draft.conversion? ? @settings.quote_convert_enabled? : @settings.order_create_enabled?
    raise Invalid, 'unidade' unless @settings.order_company?(@draft.company)
    raise Invalid, 'usuario_erp' unless erp_user.positive?
    raise Invalid, 'tipo_atendimento' if @draft.fields['tipo_atendimento'].to_s.strip.empty?
    raise Invalid, 'classe' unless @draft.fields['classe'].to_i.positive?
    raise Invalid, 'sem_cliente' if @draft.fresh? && !@draft.customer_code.to_i.positive?
    raise Invalid, 'sem_itens' if @draft.fresh? && @draft.items.empty?
    raise Invalid, 'orcamento' if @draft.conversion? && !@draft.quote_number.to_i.positive?
  end

  # só o código ligado à pessoa (Configurações > usuários do ERP): o padrão da integração não serve para assinar uma OS
  def erp_user = @erp_user ||= @settings.data['user_erp_ids'].to_h[@user&.id.to_s].to_i

  def sql = @sql ||= Outsider::Erp::Orders::Sql.new(@draft, erp_user: erp_user, lock_name: lock_name)

  # o nome no aviso "em utilização" do orçamento (o desktop mostra quem está com ele): a marca do rascunho + a pessoa
  def lock_name = "#{@draft.marker} #{@user&.name.presence || 'Chatwoot'}".first(50)

  def find_order
    rows = run_sql(sql.find_sql)
    log("mais de uma OS com a marca #{@draft.marker}: #{rows.pluck('numero').join(', ')}") if rows.size > 1
    rows.first
  end

  def start_order
    checks = Outsider::Erp::Orders::Checks.new(@draft, erp_user: erp_user, client: @client, schema: @schema)
    if @draft.conversion?
      checks.conversion!(quote_state)
      reserve_quote
    else
      checks.fresh!
    end
    ensure_attendance_type!
    save(erp_result: result.merge('checks' => checks.list))
    insert_header
  rescue Outsider::Erp::Orders::Checks::Invalid => e
    save(erp_result: result.merge('checks' => e.checks))
    raise Invalid, e.message
  end

  # o tipo precisa ser um dos do ERP (lista do quadro + os já usados); lista fora do ar não impede
  def ensure_attendance_type!
    types = Outsider::Erp::Lists.new(@draft.account).attendance_types
    return if types.empty?

    normalize = ->(value) { Outsider::Erp::Prints::Bindings.normalize_type(value) }
    raise Invalid, 'tipo_atendimento' unless types.any? { |type| normalize.call(type) == normalize.call(@draft.fields['tipo_atendimento']) }
  rescue Outsider::Erp::Client::Error
    nil
  end

  def quote_state = run_sql(sql.quote_state_sql).first

  # aviso de uso do próprio Mais Prático; só segue se o aviso ficou com a nossa marca
  def reserve_quote
    @client.query_execute(sql.reserve_quote_sql)
    state = quote_state
    raise Invalid, 'orcamento_em_uso' unless state && state['em_uso_por'].to_s == lock_name

    @reserved = true
    step('reservado')
  end

  # um comando só, com o número calculado nele; recusado (número pego no mesmo instante) ou sem resposta, procura pela
  # marca e tenta de novo
  def insert_header
    statement = header_statement
    HEADER_TRIES.times do
      begin
        @client.query_execute(statement)
      rescue Outsider::Erp::Client::Error => e
        @header_error = e.message
      end
      found = find_order
      return found if found
    end
    raise Invalid, @header_error ? 'cabecalho_recusado' : 'cabecalho_nao_gravado'
  end

  def header_statement
    return sql.fresh_header_sql unless @draft.conversion?

    sql.conversion_header_sql(@schema.columns(@draft.company, 'os'), @schema.columns(@draft.company, 'orcamento'))
  end

  def remember(number, order)
    save(erp_number: number, erp_result: result.merge('header' => order.slice('situacao', 'tipo', 'tecnico', 'maquina', 'serie')))
    step('cabecalho')
    log("OS #{@draft.company}/#{number}")
  end

  def history(number)
    ['STATUS', 'TIPO DE ATENDIMENTO'].each { |origin| @client.query_execute(sql.history_sql(number, origin)) }
    step('historico')
  end

  # uma linha por item, na ordem; a que já está lá não entra de novo
  def lines(number)
    if @draft.conversion?
      copy = Outsider::Erp::Orders::Sql.copy_columns(@schema.columns(@draft.company, 'detalheorcamento'), item_columns)
      quote_items.each_with_index do |item, index|
        @client.query_execute(sql.conversion_item_sql(number, index + 1, item['item'], copy, item_columns))
      end
    else
      @draft.items.each_with_index { |item, index| @client.query_execute(sql.fresh_item_sql(number, index + 1, item)) }
    end
    step('itens')
  end

  def item_columns = @item_columns ||= @schema.columns(@draft.company, 'detalheos')
  def quote_items = @quote_items ||= run_sql(sql.quote_items_sql)

  # somas dos impostos no cabeçalho e o orçamento FECHADO com o número da OS (só se a reserva ainda for nossa)
  def finish_conversion(number)
    statement = sql.conversion_sums_sql(number, @schema.columns(@draft.company, 'os'))
    @client.query_execute(statement) if statement
    step('somas')
    return if quote_closed?(number)

    reserve_quote unless @reserved
    @client.query_execute(sql.close_quote_sql(number))
    raise Invalid, 'orcamento_nao_fechado' unless quote_closed?(number)

    @reserved = false
    step('orcamento_fechado')
  end

  def quote_closed?(number)
    state = quote_state
    state && state['os'].to_i == number && state['status'].to_s.strip.upcase == Outsider::Erp::Orders::Sql::CLOSED
  end

  # falhou com o orçamento reservado e ainda aberto: tira o nosso aviso (falha aqui só fica no log)
  def release_quote
    return unless @reserved

    @client.query_execute(sql.release_quote_sql)
  rescue Outsider::Erp::Client::Error => e
    log("aviso de uso do orçamento não saiu: #{e.message}")
  end

  # sub status "Agendar atendimento" pelas rotas oficiais do quadro (troca + histórico), uma vez só. Falhar aqui não
  # desfaz a OS: fica o aviso
  def schedule(number)
    return if @draft.step?('agendado')

    value = schedule_value
    body = { 'listaEmpresas' => @settings.companies, 'Empresa' => @draft.company }
    @client.update('UpdateSubStatusOS', number, body.merge('SubStatus' => value))
    @client.update('GravaHistoricoSubStatusOS', number,
                   body.merge('SubStatusAntigo' => value, 'SubStatusNovo' => value, 'idUsuario' => erp_user.to_s))
    step('agendado')
  rescue Outsider::Erp::Client::Error => e
    @schedule_error = e.message
  end

  def schedule_value
    found = run_sql("SELECT S.`descricao` AS valor FROM #{Outsider::Erp::Sql.ident(@draft.company)}.substatusos S")
            .map { |row| row['valor'].to_s.squish }.find { |value| value.match?(AGENDAR) }
    found || '1- AGENDAR ATENDIMENTO'
  rescue Outsider::Erp::Client::Error
    '1- AGENDAR ATENDIMENTO'
  end

  # leitura de volta: cabeçalho, linhas do histórico e itens, para a tela mostrar o que ficou no ERP
  def finish(number)
    order = find_order.to_h
    lines = run_sql(sql.lines_sql(number))
    expected = @draft.conversion? ? quote_items.size : @draft.items.size
    readback = {
      'situacao' => order['situacao'], 'tipo' => order['tipo'], 'tecnico' => order['tecnico'], 'maquina' => order['maquina'],
      'serie' => order['serie'], 'orcamento' => order['orcamento'], 'historico' => run_sql(sql.history_count_sql(number)).first.to_h['linhas'].to_i,
      'itens' => lines.size, 'itens_esperados' => expected
    }
    save(status: :created, erp_created_at: Time.current,
         erp_result: result.except('error').merge('readback' => readback, 'schedule_error' => @schedule_error).compact)
    log("gravada #{@draft.company}/#{number}: #{lines.size} de #{expected} itens")
    @draft
  end

  def with_lock(name, wait:)
    key = "outsider_erp:#{@draft.account_id}:#{name}"
    deadline = Time.current + wait
    until Redis::Alfred.set(key, '1', nx: true, ex: LOCK_SECONDS)
      raise Invalid, 'em_andamento' if Time.current >= deadline

      sleep 1
    end
    begin
      yield
    ensure
      Redis::Alfred.delete(key)
    end
  end

  def run_sql(statement) = Array.wrap(@client.query_execute(statement)).grep(Hash)

  def result = @draft.erp_result.to_h

  def step(name)
    save(erp_result: result.merge('steps' => (@draft.steps | [name])))
  end

  # fora de transação: o número e cada passo ficam salvos mesmo se a próxima chamada ao ERP falhar
  def save(attributes)
    @draft.update_columns(attributes.merge(updated_at: Time.current)) # rubocop:disable Rails/SkipsModelValidations
  end

  def log(text)
    Rails.logger.info("[Outsider::Erp] conta #{@draft.account_id} usuário #{@user&.id} OS do chat #{@draft.id}: #{text}")
  end
end
