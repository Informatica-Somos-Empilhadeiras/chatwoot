# OUTSIDER: a conferência do estoque de uma OS do ERP (o "Libera Conferência" do Mais Prático), só leitura, para o painel
# da OS. Como o ERP guarda:
# - os.StatusSeparacao: 0 = não liberada, 2 = liberada (o estoque vê na fila), 3 = conferida, 4 = conferida em parte;
#   os.DataSeparacao (dia da liberação), os.DataSeparado (fim) e os.EmSeparacao (funcionário com a tela aberta agora);
# - detalheos.DataSeparacao (hora da liberação), QtdEntregue (quantidade conferida) e DataSeparado, por item;
# - logdetalheseparacaoos: cada conferência ("Conferência do Item" soma, "Conferência Total do Item" fecha o item,
#   "Conferência Removida do Item" estorna), com o funcionário e a hora.
# Quem liberou pelo chat vem de Outsider::Erp::OrderRelease (o ERP não guarda).
class Outsider::Erp::Orders::Conference
  S = Outsider::Erp::Sql
  STATES = { 1 => 'released', 2 => 'released', 3 => 'done', 4 => 'partial' }.freeze
  TOTAL = /total/i
  REMOVED = /removid/i

  def initialize(account, client:)
    @account = account
    @client = client
    @schema = Outsider::Erp::Schema.new(account, client: client)
  end

  # nil quando o banco da unidade não tem as colunas da separação
  def build(company, number)
    order = order_row(company, number)
    return unless order

    log = log_rows(company, number)
    items = item_rows(company, number)
    summary(company, number, order, items, log)
  end

  private

  def summary(company, number, order, items, log)
    state = state(order)
    release = Outsider::Erp::OrderRelease.where(account_id: @account.id).for_order(company, number).includes(:user).order(:id).last
    {
      'state' => state, 'released_at' => released_at(order, items), 'done_at' => (order['separada'] if %w[done partial].include?(state)),
      'by' => (person(company, order['em_separacao']) if state == 'conferring'), 'released_by' => release&.user&.name,
      'released_by_at' => release&.created_at&.iso8601, 'items' => counts(items, log),
      'log' => batches(company, log)
    }
  end

  def state(order)
    code = order['status'].to_i
    return 'none' if code.zero?

    STATES.fetch(code, 'released') == 'released' && order['em_separacao'].to_i.positive? ? 'conferring' : STATES.fetch(code, 'released')
  end

  # a hora de verdade está nos itens; a da OS é só o dia
  def released_at(order, items)
    items.filter_map { |row| row['liberada'].presence }.min || order['liberada']
  end

  # quantidade conferida por item: a do ERP (QtdEntregue) ou, sem ela, o log na ordem (total fecha, estorno zera)
  def counts(items, log)
    by_item = log.group_by { |row| row['item'].to_i }
    items.to_h do |row|
      entries = by_item.fetch(row['item'].to_i, [])
      counted = row['entregue'].nil? ? replay(entries) : row['entregue'].to_f
      [row['item'].to_i.to_s, { 'conferido' => counted, 'at' => row['separada'] || entries.last&.dig('data') }]
    end
  end

  def replay(entries)
    entries.reduce(0.0) do |sum, row|
      next 0.0 if row['operacao'].to_s.match?(REMOVED)
      next row['quantidade'].to_f if row['operacao'].to_s.match?(TOTAL)

      sum + row['quantidade'].to_f
    end
  end

  # para a linha do tempo: um evento por clique do estoque (mesma hora, operação e funcionário)
  def batches(company, log)
    names = {}
    log.chunk_while { |a, b| a['data'] == b['data'] && a['operacao'] == b['operacao'] && a['funcionario'] == b['funcionario'] }.map do |group|
      first = group.first
      code = first['funcionario'].to_i
      names[code] ||= person(company, code)
      { 'at' => first['data'], 'operacao' => first['operacao'].to_s.match?(REMOVED) ? 'removed' : 'counted',
        'itens' => group.size, 'name' => names[code] }
    end.last(30)
  end

  def person(company, code)
    return if code.to_i <= 0

    @sellers ||= Outsider::Erp::SellerName.new(@account, client: @client)
    @sellers.for_code(company, code).presence || "##{code.to_i}"
  end

  def order_row(company, number)
    return unless @schema.pick(company, 'os', %w[StatusSeparacao])

    run('SELECT IFNULL(O.StatusSeparacao, 0) AS status, O.EmSeparacao AS em_separacao, O.DataSeparacao AS liberada, ' \
        "O.DataSeparado AS separada FROM #{S.ident(company)}.os O WHERE O.CodigoOS = #{S.int(number)}").first
  end

  def item_rows(company, number)
    return [] unless @schema.pick(company, 'detalheos', %w[DataSeparacao])

    run('SELECT D.CodigoItem AS item, D.QtdEntregue AS entregue, D.DataSeparacao AS liberada, D.DataSeparado AS separada ' \
        "FROM #{S.ident(company)}.detalheos D WHERE D.CodigoOS = #{S.int(number)} ORDER BY D.CodigoItem")
  end

  def log_rows(company, number)
    return [] unless @schema.pick(company, 'logdetalheseparacaoos', %w[Operacao])

    run('SELECT L.CodigoItem AS item, L.Operacao AS operacao, L.CodigoFuncionario AS funcionario, L.Quantidade AS quantidade, ' \
        "L.Data AS data FROM #{S.ident(company)}.logdetalheseparacaoos L WHERE L.CodigoOS = #{S.int(number)} ORDER BY L.seq LIMIT 500")
  end

  def run(sql) = Array.wrap(@client.query_execute(sql)).grep(Hash)
end
