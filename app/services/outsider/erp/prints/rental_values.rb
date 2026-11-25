# OUTSIDER: os valores do contrato (Outsider::Erp::Rentals::ContractDetail) e da ficha da máquina
# (Outsider::Erp::Rentals::MachineDetail) no formato único do estúdio de relatórios (Outsider::Erp::Prints::Values):
# grupos de campos e tabelas do Outsider::Erp::Prints::Catalog já como texto (datas, valores, CNPJ) e os marcadores dos
# textos livres ({cliente}, {prazo}, {valor}...). Nada aqui acessa o ERP.
# rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/ModuleLength, Metrics/CyclomaticComplexity -- mapeamento campo a campo,
# mais fácil de ler inteiro
module Outsider::Erp::Prints::RentalValues
  PERIODS = { 'MENSAL' => 'por mês', 'SEMANAL' => 'por semana', 'ANUAL' => 'por ano', 'DIARIO' => 'por dia', 'DIÁRIO' => 'por dia' }.freeze
  TYPES = { 'LOCA' => 'Locação', 'MANUT' => 'Manutenção', 'PRESTA' => 'Prestação de serviço', 'SERVI' => 'Prestação de serviço' }.freeze

  private

  # ---- contrato ----

  def contract
    header = @raw['header'].to_h
    customer = quote_customer(@raw['cliente'].to_h)
    company = @raw['emitente'].to_h
    values = contract_values(header)
    {
      'emitter' => emitter(company),
      'groups' => {
        'contrato' => values.merge('numero' => header['numero'].to_s, 'tipo' => contract_type(header['tipo']), 'data' => date(header['data']),
                                   'pagamento' => header['pagamento'], 'vendedor' => header['vendedor_nome'], 'status' => header['status'],
                                   'unidade' => @unit_name),
        'cliente' => customer,
        'entrega' => delivery_place(header)
      }.transform_values { |group| stringify(group) },
      'tables' => { 'maquinas' => contract_machines },
      'texts' => { 'observacoes' => text(header['observacoes']) },
      'checklist' => [],
      'people' => { 'vendedor' => header['vendedor_nome'], 'cliente' => customer['nome'] },
      'placeholders' => stringify(
        values.merge('numero' => header['numero'], 'tipo' => contract_type(header['tipo']), 'cliente' => customer['nome'],
                     'documento' => customer['documento'], 'endereco_cliente' => [customer['endereco'], customer['cidade']].compact_blank.join(' - '),
                     'maquinas' => Array(@raw['maquinas']).size, 'data' => today, 'unidade' => @unit_name, 'empresa' => company['nome'],
                     'empresa_documento' => document(company['cnpj']), 'cidade' => [company['cidade'], company['uf']].compact_blank.join('/'))
      )
    }
  end

  def contract_values(header)
    period = PERIODS[header['periodicidade'].to_s.strip.upcase]
    installment = header['parcela'].to_f.positive? ? "R$ #{money(header['parcela'])}#{" #{period}" if period}" : ''
    {
      'inicio' => date(header['inicio']), 'termino' => date(header['termino']), 'prazo' => term(header),
      'valor' => installment.presence || (header['total'].to_f.positive? ? "R$ #{money(header['total'])}" : ''),
      'total' => header['total'].to_f.positive? ? "R$ #{money(header['total'])}" : '',
      'faturamento' => header['dia_faturamento'].to_i.positive? ? "Todo dia #{header['dia_faturamento'].to_i}" : ''
    }
  end

  def term(header)
    return "#{header['meses'].to_i} #{header['meses'].to_i == 1 ? 'mês' : 'meses'}" if header['meses'].to_i.positive?
    return "#{header['dias'].to_i} dias" if header['dias'].to_i.positive?

    ''
  end

  def contract_type(value)
    text = value.to_s.upcase
    TYPES.find { |key, _| text.include?(key) }&.last || value.to_s.strip.capitalize
  end

  def delivery_place(header)
    street = [header['entrega_endereco'], header['entrega_numero']].compact_blank.join(', ')
    { 'endereco' => [street, header['entrega_bairro']].compact_blank.join(' - '),
      'cidade' => [header['entrega_cidade'], header['entrega_uf']].compact_blank.join(' - '), 'obra' => header['obra'] }
  end

  def contract_machines
    Array(@raw['maquinas']).map do |row|
      stringify('descricao' => row['descricao'], 'modelo' => row['modelo'], 'serie' => row['serie'], 'patrimonio' => row['patrimonio'],
                'capacidade' => row['capacidade'], 'saida' => date(row['saida']), 'retorno' => date(row['retorno_previsto']),
                'valor' => row['valor'].to_f.positive? ? money(row['valor']) : '')
    end
  end

  # ---- ficha da máquina ----

  def machine
    header = @raw['header'].to_h
    now = @raw['agora'].to_h
    place = now['contrato'].to_h
    holder = place['cliente'].presence || @raw.dig('dono', 'nome')
    name = [header['descricao'], header['modelo']].compact_blank.first.to_s
    {
      'emitter' => emitter(@raw['emitente'].to_h),
      'groups' => {
        'maquina' => header.slice('descricao', 'modelo', 'serie', 'patrimonio', 'ano', 'capacidade', 'elevacao', 'mastro', 'altura_mastro',
                                  'rodas', 'voltagem', 'nf_aquisicao')
                           .merge('valor_locacao' => header['valor_locacao'].to_f.positive? ? "R$ #{money(header['valor_locacao'])}" : '',
                                  'garantia' => date(header['garantia']), 'inicio_operacao' => date(header['inicio_operacao']),
                                  'unidade' => @unit_name),
        'situacao' => {
          'situacao' => header['situacao'], 'cliente' => holder,
          'contrato' => place['contrato'].to_i.positive? ? "#{place['contrato']} (#{contract_type(place['tipo'])})" : '',
          'os_aberta' => now.dig('os', 'numero').to_i.positive? ? now.dig('os', 'numero').to_s : '',
          'horimetro' => hours(header['horimetro']), 'ultima_os' => date(header['ultima_os']),
          'total_os' => header['total_os'].to_i.positive? ? header['total_os'].to_s : '',
          'dono' => header['propria'].to_i == 1 ? 'Frota própria' : @raw.dig('dono', 'nome'), 'data' => today
        }
      }.transform_values { |group| stringify(group) },
      'tables' => { 'ordens' => machine_orders, 'contratos' => machine_contracts },
      'texts' => { 'descricao_tecnica' => text(header['descricao_tecnica']), 'acessorios' => text(header['acessorios']) },
      'checklist' => [],
      'people' => { 'cliente' => holder },
      'placeholders' => stringify(
        'numero' => header['numero'], 'maquina' => name, 'serie' => header['serie'], 'patrimonio' => header['patrimonio'],
        'modelo' => header['modelo'], 'cliente' => holder, 'situacao' => header['situacao'], 'data' => today, 'unidade' => @unit_name,
        'empresa' => @raw.dig('emitente', 'nome')
      )
    }
  end

  # horímetro em texto do ERP ("3412", "3.412,5") -> "3.412 h"; zero ou vazio fica vazio
  def hours(value)
    number = value.to_s.strip.delete('.').tr(',', '.').to_f
    number.positive? ? "#{ActiveSupport::NumberHelper.number_to_delimited(number.round, delimiter: '.')} h" : ''
  end

  def machine_orders
    Array(@raw['orders']).map do |row|
      stringify('numero' => row['numero'], 'data' => date(row['data']), 'atendimento' => row['atendimento'], 'status' => row['status'],
                'horimetro' => hours(row['horimetro']), 'tecnico' => row['tecnico_nome'], 'cliente' => row['cliente'])
    end
  end

  def machine_contracts
    Array(@raw['contracts']).map do |row|
      back = row['devolvida'] ? date(row['retorno']) : [date(row['retorno_previsto']), 'previsto'].compact_blank.join(' ').presence
      stringify('contrato' => row['contrato'], 'tipo' => contract_type(row['tipo']), 'cliente' => row['cliente'],
                'saida' => date(row['saida']), 'retorno' => back.to_s == 'previsto' ? '' : back, 'status' => row['contrato_status'])
    end
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/ModuleLength, Metrics/CyclomaticComplexity
