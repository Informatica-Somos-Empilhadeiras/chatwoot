# OUTSIDER: põe o hash de uma OS (Outsider::Erp::ServiceOrderReport), de um orçamento (Outsider::Erp::QuoteReport) ou de
# Locação e máquinas (contrato e ficha da máquina, Outsider::Erp::Prints::RentalValues) no
# formato único que o estúdio desenha (Outsider::Erp::Prints::Pdf no servidor e a pré-visualização na tela): os grupos
# de campos e as tabelas do Outsider::Erp::Prints::Catalog já como texto formatado (datas, valores, CNPJ), os textos
# longos, o checklist (seção > item > respostas e fotos), o emitente e os marcadores dos textos livres.
# Foto do checklist: bytes (PDF) ou { 'ref' } (tela, que busca pela rota da foto). Nada aqui acessa o ERP.
# rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- mapeamento campo a campo, mais fácil de ler inteiro
class Outsider::Erp::Prints::Values
  include Outsider::Erp::QuotePdfText
  include Outsider::Erp::Prints::RentalValues

  def initialize(kind, raw, unit_name: nil)
    @kind = kind.to_s
    @raw = raw.to_h
    @unit_name = unit_name.presence || @raw['empresa'] || @raw['company']
  end

  def build
    base = case @kind
           when 'os' then service_order
           when 'contract' then contract
           when 'machine' then machine
           else quote
           end
    base.merge('kind' => @kind, 'numero' => @raw['numero'].to_i, 'company' => @raw['empresa'] || @raw['company'],
               'preview' => @raw['previa'] == true)
  end

  private

  # ---- OS ----

  def service_order
    service = @raw['servico'].to_h
    customer = @raw['cliente'].to_h
    equipment = @raw['equipamento'].to_h
    {
      'emitter' => emitter(@raw['emitente'].to_h),
      'groups' => {
        'os' => { 'numero' => @raw['numero'].to_s, 'tipo_atendimento' => service['tipo_atendimento'], 'classificacao' => service['classificacao'],
                  'tecnico' => service['tecnico'], 'data' => today, 'unidade' => @unit_name },
        'cliente' => { 'nome' => customer['nome'], 'documento' => document(customer['documento']), 'endereco' => customer['endereco'],
                       'cidade' => customer['cidade'] },
        'equipamento' => equipment.slice('descricao', 'marca', 'modelo', 'serie', 'horimetro')
      }.transform_values { |group| stringify(group) },
      'tables' => { 'produtos' => products, 'eventos' => events, 'checklist' => checklist_rows },
      'texts' => { 'avaliacao' => text(@raw['avaliacao']), 'defeitos' => text(service['defeitos']) },
      'checklist' => checklist,
      'people' => { 'tecnico' => service['tecnico'], 'cliente' => customer['nome'] },
      'attendance_type' => service['tipo_atendimento'].to_s.squish.upcase,
      'placeholders' => stringify(
        'numero' => @raw['numero'], 'cliente' => customer['nome'], 'tipo_atendimento' => service['tipo_atendimento'],
        'tecnico' => service['tecnico'], 'equipamento' => [equipment['descricao'], equipment['modelo']].compact_blank.join(' - '),
        'data' => today, 'unidade' => @unit_name, 'empresa' => @raw.dig('emitente', 'nome')
      )
    }
  end

  def products
    Array(@raw['produtos']).map do |item|
      stringify('codigo' => item['codigo'], 'descricao' => item['descricao'], 'unidade' => item['unidade'], 'quantidade' => qty(item['quantidade']))
    end
  end

  def events
    Array(@raw['eventos']).map { |event| stringify(event.to_h.slice('tipo', 'observacoes', 'check_in', 'check_out')) }
  end

  def checklist
    Array(@raw['checklist']).map do |section|
      { 'nome' => text(section['nome']),
        'itens' => Array(section['itens']).map do |item|
          { 'atributo' => text(item['atributo']), 'chegada' => text(item['chegada']), 'saida' => text(item['saida']),
            'fotos' => Array(item['fotos']).map { |value| photo(value) } }
        end }
    end
  end

  # bytes (PDF), "<OS>_<n>" (a tela busca pela rota da foto) ou { 'sample' => arquivo } (amostra do estúdio)
  def photo(value)
    return value if value.is_a?(Hash)
    return { 'ref' => value } if value.is_a?(String) && value.match?(Outsider::Erp::ServiceOrderReport::PHOTO_REF)

    value
  end

  # as respostas do checklist em linhas (a tabela "Respostas do checklist")
  def checklist_rows
    checklist.flat_map do |section|
      section['itens'].map do |item|
        { 'secao' => section['nome'], 'item' => item['atributo'], 'chegada' => item['chegada'], 'saida' => item['saida'] }
      end
    end
  end

  # ---- orçamento ----

  def quote
    customer = @raw['cliente'].to_h
    {
      'emitter' => emitter(@raw['emitente'].to_h),
      'groups' => {
        'orcamento' => { 'numero' => @raw['numero'].to_s, 'data' => date(@raw['data']), 'vendedor' => @raw['vendedor'],
                         'pagamento' => @raw['pagamento'], 'status' => @raw['status'], 'unidade' => @unit_name },
        'cliente' => quote_customer(customer),
        'condicoes' => conditions,
        'totais' => totals
      }.transform_values { |group| stringify(group) },
      'tables' => { 'itens' => quote_items },
      'texts' => { 'observacoes' => text(@raw['observacoes']) },
      'checklist' => [],
      'people' => { 'vendedor' => @raw['vendedor'], 'cliente' => customer['nome'] },
      'placeholders' => stringify(
        'numero' => @raw['previa'] ? 'Prévia' : @raw['numero'], 'cliente' => customer['nome'], 'vendedor' => @raw['vendedor'],
        'data' => date(@raw['data']),
        'total' => "R$ #{money(@raw['total'])}", 'unidade' => @unit_name, 'empresa' => @raw.dig('emitente', 'nome')
      )
    }
  end

  def quote_customer(customer)
    address = [[customer['endereco'], customer['numero']].compact_blank.join(', '), customer['complemento'], customer['bairro']].compact_blank
    {
      'nome' => customer['nome'], 'documento' => document(customer['documento']), 'ie' => customer['ie'], 'endereco' => address.join(' - '),
      'cidade' => [customer['cidade'], customer['uf']].compact_blank.join(' - '), 'cep' => customer['cep'],
      'fone' => [customer['fone_contato'], customer['fone'], customer['celular']].compact_blank.first, 'email' => customer['email'],
      'contato' => customer['contato'], 'fantasia' => customer['fantasia']
    }
  end

  CONDITION_KEYS = {
    'Prazo de Entrega' => 'prazo_entrega', 'ICMS' => 'icms', 'Validade' => 'validade', 'Desc. Frete' => 'desc_frete',
    'Reajuste' => 'reajuste', 'IPI' => 'ipi', 'Prazo de Garantia' => 'garantia', 'Taxa de Armazenagem' => 'armazenagem',
    'Taxa de Cancelamento' => 'cancelamento', 'Cubagem' => 'cubagem', 'Quantidade de Volumes' => 'volumes'
  }.freeze
  TOTAL_KEYS = {
    'Sub-Total' => 'subtotal', 'Vr. IPI' => 'vr_ipi', 'Outras Despesas' => 'outras', 'Vr. Seguro' => 'seguro', 'Valor ST' => 'vr_st',
    'Vr. ICMS' => 'vr_icms', 'Desconto' => 'desconto', 'Acréscimo' => 'acrescimo', 'Frete' => 'frete'
  }.freeze

  def conditions
    Array(@raw['condicoes']).each_with_object({}) do |(label, value), map|
      key = CONDITION_KEYS[label]
      map[key] = value.to_s.strip if key && value.to_s.strip.present? && value.to_s.strip != '0,00 m³'
    end
  end

  # totais como "R$ 1.234,56"; zero fica vazio (o bloco de totais pode esconder)
  def totals
    values = Array(@raw['totais']).each_with_object({}) do |(label, value), map|
      key = TOTAL_KEYS[label]
      map[key] = value.to_f.zero? ? '' : "R$ #{money(value)}" if key
    end
    values.merge('total' => "R$ #{money(@raw['total'])}")
  end

  def quote_items
    Array(@raw['itens']).map do |item|
      stringify(
        'codigo' => item['codigo'], 'descricao' => item['descricao'], 'unidade' => item['unidade'], 'quantidade' => qty(item['quantidade']),
        'ncm' => item['ncm'], 'cst' => item['cst'], 'icms' => item['icms'] && money(item['icms']),
        'vr_icms' => item['vr_icms'] && money(item['vr_icms']),
        'unitario' => money(item['unitario']), 'desconto' => item['desconto'].to_f.zero? ? '' : money(item['desconto']),
        'total' => money(item['total'])
      )
    end
  end

  # ---- comuns ----

  # o cabeçalho: nome e as linhas de contato (CNPJ, endereço, telefone, e-mail, site) que existirem
  def emitter(data)
    address = [[data['endereco'], data['numero']].compact_blank.join(', '), data['bairro'],
               [data['cidade'], data['uf']].compact_blank.join('-')].compact_blank.join(' - ')
    lines = [label('CNPJ', document(data['cnpj'])), address.presence, label('Telefone', data['fone']), label('E-mail', data['email']),
             data['site'].presence].compact_blank
    { 'nome' => text(data['nome']), 'lines' => lines, 'logo' => data['logo'] }
  end

  def today = Time.zone.today.strftime('%d/%m/%Y')

  def text(value) = value.to_s.strip

  def stringify(hash) = hash.transform_values { |value| value.nil? ? '' : value.to_s.strip }
end
# rubocop:enable Metrics/AbcSize, Metrics/MethodLength
