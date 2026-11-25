# OUTSIDER: a conferência antes de gravar uma OS feita no chat (Outsider::Erp::Orders::Creator), só leitura no banco da
# unidade. Devolve a lista que a tela mostra ([{ key, ok, detail }]) e falha (Invalid) no primeiro problema que impede a
# gravação. Confere o que o Mais Prático exige do usuário do desktop: o código de funcionário existe e tem a permissão
# (Inclusão em OS ou "Conversão OS" no acesso a orçamento), o cliente existe, a máquina existe na unidade (e é
# obrigatória onde a empresa exige), cada peça existe e não está bloqueada para venda e, na conversão, o orçamento está em
# NEGOCIAÇÃO, sem OS, sem pedido e sem ninguém com ele aberto. Também confere se as colunas que a gravação usa existem
# (uma atualização do Mais Prático que mude a estrutura desliga a gravação com aviso, em vez de gravar pela metade).
class Outsider::Erp::Orders::Checks
  class Invalid < StandardError
    attr_reader :checks

    def initialize(reason, checks)
      @checks = checks
      super(reason)
    end
  end

  S = Outsider::Erp::Sql
  OS_COLUMNS = %w[CodigoOS TipoAtendimento Situacao CodigoCliente CPF_CNPJ Tecnico Atendente IDLogado DataEntrada Hora DataPrevisao
                  Horimetro CodigoMaquina NSerie Defeitos ClasseOS IsCliente StatusMaquina CodigoPedidoOutroSistema Orcamento].freeze
  ITEM_COLUMNS = %w[CodigoOS CodigoItem Ordem CodigoProduto Quantidade precounitario TotalLinha].freeze
  QUOTE_COLUMNS = %w[codigoorcamento Status CodigoCliente OrdemServico ConvertidoPor DataStatus OrcamentoEmUtilizacao CodUserEmUtilizacao
                     NomeUserEmUtilizacao DataEmUtilizacao Pedido].freeze

  attr_reader :list

  def initialize(draft, erp_user:, client:, schema:)
    @draft = draft
    @erp_user = erp_user.to_i
    @client = client
    @schema = schema
    @list = []
    @bank = S.ident(draft.company)
  end

  # Nova OS
  def fresh!
    structure!(include_quote: false)
    person!('os')
    customer!(@draft.customer_code)
    machine!
    products!
    @list
  end

  # conversão. machine: false na prévia (a máquina ainda vai ser escolhida na tela)
  def conversion!(quote_row, machine: true)
    structure!(include_quote: true)
    person!('orcamento')
    quote!(quote_row)
    customer!(quote_row['cliente'])
    machine! if machine
    @list
  end

  def machine_required?
    rows("SELECT IFNULL(MAX(`ckObrigaPreencherMaquinaOS`), 1) AS obriga FROM #{@bank}.empresa").first.to_h['obriga'].to_i == 1
  rescue Outsider::Erp::Client::Error
    true
  end

  private

  def structure!(include_quote:)
    missing = missing_columns('os', OS_COLUMNS) + missing_columns('detalheos', ITEM_COLUMNS)
    missing += missing_columns('orcamento', QUOTE_COLUMNS) if include_quote
    fail!('estrutura', missing.join(', ')) if missing.any?
    add('estrutura', true)
  end

  def missing_columns(table, needed)
    existing = @schema.columns(@draft.company, table).to_set(&:downcase)
    needed.reject { |column| existing.include?(column.downcase) }.map { |column| "#{table}.#{column}" }
  end

  # o usuário do ERP de quem grava: existe e tem a mesma permissão que o Mais Prático exige no desktop
  def person!(screen)
    fail!('usuario_erp', nil) unless @erp_user.positive?

    name = Outsider::Erp::SellerName.new(@draft.account, client: @client).for_code(@draft.company, @erp_user)
    fail!('usuario_erp', @erp_user.to_s) if name.blank?

    allowed = permission(screen)
    fail!(screen == 'os' ? 'permissao_os' : 'permissao_conversao', name) unless allowed
    add(screen == 'os' ? 'permissao_os' : 'permissao_conversao', true, name)
  end

  def permission(screen)
    sql = if screen == 'os'
            "SELECT IFNULL(MAX(A.`Inclusao`), 0) AS pode FROM #{@bank}.ac_os A WHERE A.`Funcionario` = #{S.int(@erp_user)}"
          else
            "SELECT IFNULL(MAX(A.`ConversaoOS`), 0) AS pode FROM #{@bank}.ac_orcamento A WHERE A.`Funcionario` = #{S.int(@erp_user)}"
          end
    rows(sql).first.to_h['pode'].to_i == 1
  end

  def customer!(code)
    fail!('cliente', nil) unless code.to_i.positive?

    row = rows("SELECT C.`CodigoCliente` AS codigo, C.`Nome` AS nome, C.`CPF_CNPJ` AS documento#{active_column('clientes', 'C')} " \
               "FROM #{@bank}.clientes C WHERE C.`CodigoCliente` = #{S.int(code)}").first
    fail!('cliente', code.to_s) unless row
    fail!('cliente_inativo', row['nome'].to_s) if row.key?('ativo') && row['ativo'].to_s == '0'

    add('cliente', true, "#{row['codigo']} · #{row['nome'].to_s.squish}")
  end

  # máquina: obrigatória onde a empresa marca ckObrigaPreencherMaquinaOS; existindo, precisa estar no cadastro da unidade
  def machine!
    code = @draft.fields['maquina'].to_i
    if code <= 0
      fail!('maquina_obrigatoria', nil) if machine_required?
      return add('maquina', true, nil)
    end

    row = rows("SELECT E.`Seq` AS codigo, E.`NSerie` AS serie, E.`CodClientes` AS cliente FROM #{@bank}.equipamentos E " \
               "WHERE E.`Seq` = #{S.int(code)}").first
    fail!('maquina', code.to_s) unless row
    add('maquina', true, [row['codigo'], row['serie'].to_s.squish.presence].compact.join(' · série '))
  end

  # peças e serviços da Nova OS: existem e não estão bloqueados para venda
  def products!
    codes = @draft.items.map { |item| item['codigo'].to_i }.uniq
    fail!('sem_itens', nil) if codes.empty?

    blocked = @schema.pick(@draft.company, 'produtos', %w[ckBloqueadoVenda])
    sql = "SELECT P.`CodigoProduto` AS codigo#{", P.#{S.column(blocked)} AS bloqueado" if blocked} FROM #{@bank}.produtos P " \
          "WHERE P.`CodigoProduto` IN (#{codes.map { |code| S.int(code) }.join(', ')})"
    found = rows(sql).index_by { |row| row['codigo'].to_i }
    missing = codes - found.keys
    fail!('produto_inexistente', missing.join(', ')) if missing.any?

    locked = found.values.select { |row| row['bloqueado'].to_i == 1 }.map { |row| row['codigo'] }
    fail!('produto_bloqueado', locked.join(', ')) if locked.any?
    add('produtos', true, codes.size.to_s)
  end

  def quote!(row)
    fail!('orcamento', @draft.quote_number.to_s) unless row
    fail!('orcamento_status', row['status'].to_s) unless row['status'].to_s.strip.upcase == Outsider::Erp::Orders::Sql::NEGOTIATION
    fail!('orcamento_com_os', (row['os'].presence || row['os_ligada']).to_s) if row['os'].to_i.positive? || row['os_ligada'].to_i.positive?
    fail!('orcamento_com_pedido', row['pedido'].to_s) if row['pedido'].to_i.positive?
    if row['em_uso'].to_i == 1 && row['em_uso_recente'].to_i == 1 && !ours?(row['em_uso_por'])
      fail!('orcamento_em_uso', row['em_uso_por'].to_s.squish)
    end
    fail!('orcamento_sem_itens', nil) if row['itens'].to_i.zero?

    add('orcamento', true, row['itens'].to_s)
  end

  def ours?(name) = name.to_s.start_with?("#{@draft.marker} ")

  def active_column(table, table_alias)
    column = @schema.pick(@draft.company, table, %w[Ativo])
    column ? ", #{table_alias}.#{S.column(column)} AS ativo" : ''
  end

  def rows(sql) = Array.wrap(@client.query_execute(sql)).grep(Hash)

  def add(key, ok, detail = nil) = @list << { 'key' => key, 'ok' => ok, 'detail' => detail.presence }.compact

  def fail!(key, detail)
    add(key, false, detail)
    raise Invalid.new(key, @list)
  end
end
