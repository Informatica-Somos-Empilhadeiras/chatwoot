# OUTSIDER: o "cardápio" de cada tipo de relatório do estúdio (Outsider::Erp::Prints): os grupos de campos (Dados da OS,
# Cliente, Equipamento...), as tabelas e as colunas delas, os textos longos e os marcadores que os textos livres aceitam
# ({numero}, {cliente}...). Cada campo tem a chave, o rótulo e se já vem ligado. Quem lê os valores é
# Outsider::Erp::Prints::Values; a ordem e o liga/desliga de cada modelo ficam no content['fields'] dele.
# contract (contrato de locação/manutenção) e machine (ficha da máquina) são de Locação e máquinas.
# rubocop:disable Metrics/ModuleLength -- o cardápio inteiro num lugar só
module Outsider::Erp::Prints::Catalog
  KINDS = %w[os quote contract machine].freeze

  # [chave, rótulo, ligado por padrão]
  GROUPS = {
    'os' => {
      'os' => ['Dados da OS', [%w[numero Número], ['tipo_atendimento', 'Tipo de atendimento'], %w[classificacao Classificação],
                               ['tecnico', 'Técnico principal'], ['data', 'Data de impressão', false], ['unidade', 'Unidade', false]]],
      'cliente' => ['Cliente', [%w[nome Cliente], %w[documento CNPJ/CPF], %w[endereco Endereço], %w[cidade Cidade]]],
      'equipamento' => ['Equipamento', [%w[descricao Descrição], %w[marca Marca], %w[modelo Modelo], ['serie', 'Nº série'],
                                        %w[horimetro Horímetro]]]
    },
    'quote' => {
      'orcamento' => ['Dados do orçamento', [%w[numero Número], %w[data Data], %w[vendedor Vendedor], ['pagamento', 'Forma de pagamento'],
                                             ['status', 'Situação', false], ['unidade', 'Unidade', false]]],
      'cliente' => ['Cliente', [%w[nome Cliente], %w[documento CNPJ/CPF], ['ie', 'Inscrição estadual', false], %w[endereco Endereço],
                                %w[cidade Cidade], ['cep', 'CEP', false], %w[fone Telefone], ['email', 'E-mail', false],
                                %w[contato Contato], ['fantasia', 'Nome fantasia', false]]],
      'condicoes' => ['Condições', [['prazo_entrega', 'Prazo de entrega'], %w[validade Validade], ['garantia', 'Prazo de garantia'],
                                    ['icms', 'ICMS', false], ['ipi', 'IPI', false], ['reajuste', 'Reajuste', false],
                                    ['desc_frete', 'Desc. frete', false], ['armazenagem', 'Taxa de armazenagem', false],
                                    ['cancelamento', 'Taxa de cancelamento', false], ['cubagem', 'Cubagem', false],
                                    ['volumes', 'Quantidade de volumes', false]]],
      'totais' => ['Totais', [%w[subtotal Subtotal], %w[desconto Desconto], %w[frete Frete], ['vr_ipi', 'Valor IPI', false],
                              ['vr_st', 'Valor ST', false], ['vr_icms', 'Valor ICMS', false], ['outras', 'Outras despesas', false],
                              ['seguro', 'Seguro', false], ['acrescimo', 'Acréscimo', false], %w[total Total]]]
    },
    'contract' => {
      'contrato' => ['Dados do contrato', [%w[numero Número], %w[tipo Tipo], %w[data Emissão], %w[inicio Início], %w[termino Término],
                                           %w[prazo Prazo], ['valor', 'Valor por período'], ['total', 'Total do contrato'],
                                           %w[faturamento Faturamento], ['pagamento', 'Forma de pagamento'], %w[vendedor Vendedor],
                                           ['status', 'Situação', false], ['unidade', 'Unidade', false]]],
      'cliente' => ['Cliente', [%w[nome Cliente], %w[documento CNPJ/CPF], ['ie', 'Inscrição estadual', false], %w[endereco Endereço],
                                %w[cidade Cidade], ['cep', 'CEP', false], %w[fone Telefone], ['email', 'E-mail', false],
                                %w[contato Contato]]],
      'entrega' => ['Local de entrega', [%w[endereco Endereço], %w[cidade Cidade], %w[obra Obra]]]
    },
    'machine' => {
      'maquina' => ['Máquina', [%w[descricao Descrição], %w[modelo Modelo], ['serie', 'Nº série'], %w[patrimonio Patrimônio],
                                %w[ano Ano], %w[capacidade Capacidade], %w[elevacao Elevação], %w[mastro Mastro],
                                ['altura_mastro', 'Altura do mastro', false], %w[rodas Rodas], %w[voltagem Voltagem],
                                ['valor_locacao', 'Valor de locação', false], ['garantia', 'Garantia até', false],
                                ['inicio_operacao', 'Início de operação', false], ['nf_aquisicao', 'NF de aquisição', false],
                                ['unidade', 'Unidade', false]]],
      'situacao' => ['Situação', [%w[situacao Situação], ['cliente', 'Cliente atual'], %w[contrato Contrato], ['os_aberta', 'OS aberta'],
                                  %w[horimetro Horímetro], ['ultima_os', 'Última OS'], ['total_os', 'Total de OS', false], %w[dono Dono],
                                  ['data', 'Data de impressão', false]]]
    }
  }.freeze

  # tabelas: [rótulo, colunas [chave, rótulo, ligada, alinhamento]]
  TABLES = {
    'os' => {
      'produtos' => ['Produtos', [%w[codigo Código], %w[descricao Descrição], %w[unidade Un.], ['quantidade', 'Qtd.', true, 'right']]],
      'eventos' => ['Check-in / check-out', [%w[tipo Tipo], %w[observacoes Observações], %w[check_in Check-in], %w[check_out Check-out]]],
      'checklist' => ['Respostas do checklist', [%w[secao Seção], %w[item Item], %w[chegada Chegada], %W[saida Sa\u00EDda]]]
    },
    'quote' => {
      'itens' => ['Peças e serviços', [%w[codigo Código], %w[descricao Descrição], %w[unidade Un.], ['quantidade', 'Qtd.', true, 'right'],
                                       ['ncm', 'NCM', false], ['cst', 'CST', false], ['icms', 'ICMS %', false, 'right'],
                                       ['vr_icms', 'Vr. ICMS', false, 'right'], ['unitario', 'Unitário', true, 'right'],
                                       ['desconto', 'Desconto', false, 'right'], ['total', 'Total', true, 'right']]]
    },
    'contract' => {
      'maquinas' => ['Máquinas do contrato', [%w[descricao Máquina], %w[modelo Modelo], ['serie', 'Nº série'],
                                              ['patrimonio', 'Patrimônio', false], ['capacidade', 'Capacidade', false], %w[saida Saída],
                                              ['retorno', 'Retorno previsto'], ['valor', 'Valor', true, 'right']]]
    },
    'machine' => {
      'ordens' => ['Ordens de serviço', [%w[numero OS], %w[data Data], %w[atendimento Atendimento], %w[status Situação],
                                         ['horimetro', 'Horímetro', true, 'right'], %w[tecnico Técnico], ['cliente', 'Cliente', false]]],
      'contratos' => ['Contratos', [%w[contrato Contrato], %w[tipo Tipo], %w[cliente Cliente], %w[saida Saída], %w[retorno Retorno],
                                    ['status', 'Situação', false]]]
    }
  }.freeze

  TEXTS = {
    'os' => { 'avaliacao' => 'Avaliação técnica', 'defeitos' => 'Defeitos mencionados' },
    'quote' => { 'observacoes' => 'Observações' },
    'contract' => { 'observacoes' => 'Observações do contrato' },
    'machine' => { 'descricao_tecnica' => 'Descrição técnica', 'acessorios' => 'Acessórios' }
  }.freeze

  PLACEHOLDERS = {
    'os' => { 'numero' => 'Número da OS', 'cliente' => 'Cliente', 'tipo_atendimento' => 'Tipo de atendimento',
              'tecnico' => 'Técnico', 'equipamento' => 'Equipamento', 'data' => 'Data de impressão', 'unidade' => 'Unidade',
              'empresa' => 'Empresa emitente' },
    'quote' => { 'numero' => 'Número do orçamento', 'cliente' => 'Cliente', 'vendedor' => 'Vendedor', 'data' => 'Data',
                 'total' => 'Total', 'unidade' => 'Unidade', 'empresa' => 'Empresa emitente' },
    'contract' => { 'numero' => 'Número do contrato', 'tipo' => 'Tipo do contrato', 'cliente' => 'Cliente', 'documento' => 'CNPJ/CPF do cliente',
                    'endereco_cliente' => 'Endereço do cliente', 'inicio' => 'Início', 'termino' => 'Término', 'prazo' => 'Prazo',
                    'valor' => 'Valor por período', 'total' => 'Total do contrato', 'faturamento' => 'Faturamento',
                    'maquinas' => 'Quantidade de máquinas', 'data' => 'Data de impressão', 'unidade' => 'Unidade',
                    'empresa' => 'Empresa emitente', 'empresa_documento' => 'CNPJ da empresa', 'cidade' => 'Cidade da empresa' },
    'machine' => { 'numero' => 'Número do cadastro', 'maquina' => 'Máquina', 'serie' => 'Nº série', 'patrimonio' => 'Patrimônio',
                   'modelo' => 'Modelo', 'cliente' => 'Cliente atual', 'situacao' => 'Situação', 'data' => 'Data de impressão',
                   'unidade' => 'Unidade', 'empresa' => 'Empresa emitente' }
  }.freeze

  module_function

  def groups(kind) = GROUPS.fetch(kind.to_s)
  def tables(kind) = TABLES.fetch(kind.to_s)
  def texts(kind) = TEXTS.fetch(kind.to_s)

  # grupos e tabelas são listas de campos com ordem e liga/desliga (content['fields'])
  def lists(kind)
    groups(kind).transform_values { |_label, fields| fields.map { |key, _, on| [key, on != false] } }
                .merge(tables(kind).transform_values { |_label, columns| columns.map { |key, _, on| [key, on != false] } })
  end

  # o que a tela do estúdio precisa para montar a paleta, a aba Campos e os rótulos
  def to_h(kind)
    {
      'kind' => kind.to_s,
      'groups' => groups(kind).map { |key, (label, fields)| { 'key' => key, 'label' => label, 'fields' => field_list(fields) } },
      'tables' => tables(kind).map { |key, (label, columns)| { 'key' => key, 'label' => label, 'columns' => field_list(columns) } },
      'texts' => texts(kind).map { |key, label| { 'key' => key, 'label' => label } },
      'placeholders' => PLACEHOLDERS.fetch(kind.to_s).map { |key, label| { 'key' => key, 'label' => label } },
      'blocks' => Outsider::Erp::Prints::Content.block_types(kind)
    }
  end

  def field_list(fields)
    fields.map { |key, label, on, align| { 'key' => key, 'label' => label, 'on' => on != false, 'align' => align || 'left' } }
  end

  def label(kind, list, key)
    entry = groups(kind)[list] || tables(kind)[list]
    entry&.last&.find { |field| field.first == key }&.second || key
  end
end
# rubocop:enable Metrics/ModuleLength
