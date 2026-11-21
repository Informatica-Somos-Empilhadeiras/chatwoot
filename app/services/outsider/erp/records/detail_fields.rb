# OUTSIDER: os campos do detalhe da seção ERP por tipo (orçamento, OS, pedido, NF-e, NFS-e): tabela, chave, tabela dos
# itens e, para cada campo do painel, as colunas candidatas (a primeira que existir no banco da unidade, conferida por
# Outsider::Erp::Schema). Só descreve; quem lê é Outsider::Erp::Records::Detail.
module Outsider::Erp::Records::DetailFields
  COMMON = {
    'data' => nil, 'status' => nil, 'total' => %w[total Total], 'cliente_codigo' => %w[CodigoCliente], 'contato' => %w[Contato],
    'telefone' => %w[Telefone], 'observacoes' => %w[Observacoes Observacao], 'pagamento' => %w[FormaPagto]
  }.freeze
  DEFINITIONS = {
    'quotes' => {
      table: 'orcamento', key: %w[codigoorcamento CodigoOrcamento], items_table: 'detalheorcamento', items_key: %w[CodigoOrcamento],
      header: {
        'data' => %w[orcamentoData], 'status' => %w[Status], 'vendedor' => %w[Vendedor], 'iniciado_por' => %w[IDLogado],
        'validade' => %w[Validade], 'prazo_entrega' => %w[PrazoEntrega], 'garantia' => %w[PrazoGarantia], 'frete' => %w[Frete],
        'desconto' => %w[descontototal], 'servicos' => %w[totalServicos], 'os' => %w[OrdemServico], 'data_status' => %w[DataStatus],
        'autorizado_por' => %w[AutorizadoPor], 'data_autorizado' => %w[DataAutorizadoPor], 'chat' => %w[CodigoIntegracaoMobile],
        'em_uso' => %w[OrcamentoEmUtilizacao], 'em_uso_por' => %w[NomeUserEmUtilizacao], 'em_uso_desde' => %w[DataEmUtilizacao]
      }
    },
    'orders' => {
      table: 'os', key: %w[CodigoOS], items_table: 'detalheos', items_key: %w[CodigoOS],
      header: {
        'data' => %w[DataEntrada], 'status' => %w[Situacao], 'substatus' => %w[SubStatus], 'atendimento' => %w[TipoAtendimento],
        'tecnico' => %w[Tecnico], 'vendedor' => %w[Vendedor], 'previsao' => %w[DataPrevisao], 'entrega' => %w[DataEntrega],
        'validade' => %w[DataValidade], 'serie' => %w[NSerie], 'horimetro' => %w[Horimetro], 'garantia' => %w[Garantia],
        'defeitos' => %w[Defeitos], 'acessorios' => %w[Acessorios], 'equipamento' => %w[Modelo DescricaoMaquina Equipamento],
        'orcamento' => %w[Orcamento], 'pedido' => %w[Pedido], 'produtos' => %w[TotalProdutos], 'servicos' => %w[TotalServicos]
      }
    },
    'sales' => {
      table: 'pedido', key: %w[CodigoPedido], items_table: 'detalhepedido', items_key: %w[CodigoPedido],
      header: {
        'data' => %w[PedidoData], 'status' => %w[Status Situacao], 'vendedor' => %w[Vendedor], 'orcamento' => %w[orcamento Orcamento],
        'os' => %w[OS], 'fechado' => %w[fechado], 'entrega' => %w[DataEntrega], 'frete' => %w[Frete], 'desconto' => %w[descontototal],
        'faturado_em' => %w[DataFaturado DataFaturamento]
      }
    },
    # NF-e (produtos); TipoNota 0 = saída, 1 = entrada. O número e a série saem também da chave de acesso
    'invoices' => {
      table: 'notafiscal', key: %w[CodigoNF], items_table: 'detalhenf', items_key: %w[CodigoNF],
      header: {
        'data' => %w[Emissao], 'status' => %w[Status], 'total' => %w[TotalNF total], 'tipo' => %w[TipoNota], 'natureza' => %w[Natureza],
        'cfop' => %w[CFOP], 'vendedor' => %w[Vendedor], 'pedido' => %w[Pedido], 'orcamento' => %w[orcamento], 'os' => %w[OS],
        'saida' => %w[DataSaida], 'chave' => %w[chaveacesso], 'protocolo' => %w[protocolo], 'cancelamento' => %w[motivocancelamento],
        'data_cancelamento' => %w[DataCancelamento], 'produtos' => %w[TotalProdutos], 'servicos' => %w[totalservico], 'frete' => %w[Frete],
        'desconto' => %w[DescontoTotal]
      }
    },
    # NFS-e (serviços): a chave é a sequência interna; o número da prefeitura (CodigoNFS) só vem depois de impressa
    'service_invoices' => {
      table: 'notafiscalservico', key: %w[SeqNFSe], items_table: 'detalhenfservico', items_key: %w[SeqNFSe],
      header: {
        'data' => %w[Emissao], 'status' => %w[Status], 'total' => %w[TotalNF Total], 'cliente_codigo' => %w[CodigoDestinatario],
        'e_cliente' => %w[isCliente], 'telefone' => %w[TelResidencia], 'nfse' => %w[CodigoNFS], 'rps' => %w[CodigoRps],
        'verificacao' => %w[CodigoVerificacao], 'vendedor' => %w[Vendedor], 'pedido' => %w[Pedido], 'competencia' => %w[DataCompetencia],
        'cancelamento' => %w[MotivoCancelamento], 'data_cancelamento' => %w[DataCancelamento], 'servicos' => %w[TotalServicos],
        'tributos' => %w[TotalTributos], 'desconto' => %w[DescontoTotal]
      }
    }
  }.freeze
  ITEMS = {
    'quantidade' => %w[Quantidade quantidade], 'unitario' => %w[PrecoUnitario precounitario], 'desconto' => %w[PercDesconto descperc],
    'total' => %w[TotalLinha]
  }.freeze
end
