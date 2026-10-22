# OUTSIDER: os dois modelos de proposta que a conta recebe na primeira vez que abre as propostas, copiados
# das propostas da Somos (venda 2597 e locação 2661). Textos com **negrito** e campos automáticos entre
# chaves ({cliente.empresa}, {proposta.validade}...; ver Outsider::Crm::ProposalPdf::Fields). Dados da
# empresa (CNPJ, endereço, banco) não ficam aqui: vêm de Configurações > Propostas.
module Outsider::Crm::ProposalTemplateDefaults
  module_function

  COMMON = {
    'show_specs' => true,
    'show_bank' => true,
    'validity_days' => 5,
    'order_heading' => 'Confirmação de pedido deverá ser emitido para:',
    'bank_heading' => 'Dados Bancários:',
    'documents_heading' => 'Documentação enviar para:',
    'default_letterhead' => true
  }.freeze

  SALE_CONDITIONS = [
    ['Pagamento com recurso próprio', '30% ENTRADA - SALDO EM 10X NO BOLETO SEM JUROS. (Mediante aprovação de crédito)'],
    ["**Documentos para análise de crédito PJ:**\n\n* Primeira compra",
     "Proposta assinada com CNPJ e pedido interno assinado quando houver**\n\n- Relação de faturamento dos últimos 12 meses\n" \
     "- Balanço e DRE (último exercício)\n- Imposto de renda dos sócios\n- Ficha Cadastral\n- Documentos dos sócios\n- CNPJ\n" \
     "- Contrato Social\n- Inscrição Estadual"],
    ["**Documentos para análise de crédito PF:**\n\n* Primeira compra",
     "Proposta assinada com CPF e pedido interno assinado quando houver**\n\n**1. Documentos Pessoais**\n" \
     "- RG (Registro Geral) ou CNH (Carteira Nacional de Habilitação)\n- CPF (Cadastro de Pessoa Física)\n- Comprovante de residência\n" \
     "**2. Comprovantes de Renda**\n- Declaração de Imposto de Renda (IR)\n- Extrato bancário"],
    ['Local de retirada:', '**SOMOS EMPILHADEIRAS - MATRIZ GOIÂNIA - GO**'],
    ['Frete:', '**CIF - Posto no Cliente**'],
    ['Prazo de entrega:',
     '**ATÉ 05 DIAS DO PEDIDO / CONFIRMAÇÃO DE PAGAMENTO DE SINAL** / SALVO VENDA PRÉVIA – conforme disponibilidade de estoque.'],
    ['Entrega técnica:',
     'A entrega técnica será efetuada por um técnico especializado no local de entrega. Ao ser realizada a entrega técnica, ' \
     'serão repassadas todas as instruções de funcionamento e manutenção preventiva do equipamento, bem como catálogo de peças ' \
     'e manuais de operação e serviço.'],
    ['**Impostos:**',
     'Esta operação contempla a alíquota de ICMS vigente para os estados de GO, DF e BA, aplicada com a redução de base de cálculo ' \
     "conforme a legislação estadual pertinente.\nPara faturamento destinado a qualquer unidade federativa exceto GO, DF e BA, será " \
     "considerada a alíquota interestadual de 4%.\nValores exclusivos para clientes Contribuintes de ICMS.\nQualquer tributação " \
     'posterior (como Diferencial de Alíquota ou Substituição Tributária no destino) é de inteira responsabilidade do adquirente.'],
    ['Garantia:',
     '• Garantia do equipamento **12 meses ou 2000 horas**, o que ocorrer primeiro. Desde que sejam seguidos todos os requisitos ' \
     'descritos em nosso CERTIFICADO DE GARANTIA e manual de manutenção e operação (segue com o equipamento), realização da ' \
     'entrega técnica do equipamento, execução de manutenção preventiva (conforme severidade da operação), realização da revisão ' \
     "final de garantia, a utilização de peças genuínas e atendimentos realizados por nossa rede de Serviços Autorizados.\n" \
     '• O cliente deverá realizar a comunicação com o serviço autorizado mais próximo da sua unidade, se a máquina for transferida ' \
     'para outra região, afim de envolvermos o respectivo serviço autorizado para alinhar a entrega técnica e outros atendimentos, ' \
     'caso não seja realizado a garantia será comprometida.'],
    ['Atraso de Pagamento:',
     'O atraso do pagamento de qualquer parcela, mesmo que por atraso na obtenção da Fiança Bancária, implicará em cobrança de ' \
     'multa e 10% de custo financeiro, conforme taxas mercado.'],
    ['Taxa de Cancelamento:', 'Para máquina Standard 10% e para máquina fora do padrão 30%, sobre o valor total do pedido'],
    ['**Validade da proposta**', '{proposta.validade}']
  ].freeze

  RENTAL_CONDITIONS = [
    ['Prazo de entrega', '07 dias, conforme condições gerais'],
    ['VALIDADE DA PROPOSTA', '{proposta.validade}'],
    ['FRETE', 'Goiânia-GO para Cliente – 100% por conta da Proponente. CIF'],
    ['Prazo contratual', '02 meses'],
    ['Franquia', '300 horas mês'],
    ['ENTREGA TÉCNICA',
     'A entrega técnica será efetuada por um técnico especializado no local de entrega e assim serão dadas todas as instruções de ' \
     'funcionamento e manutenção preventiva do equipamento, bem como catálogos de peças e manuais de operação e serviços.'],
    ['Manutenções', 'Por conta da locadora, exceto mau uso.'],
    ['**Taxa de Cancelamento**',
     'Para máquinas Standard, será aplicada uma taxa de 10% sobre o valor total do pedido. Para máquinas fora do padrão, a taxa ' \
     'será de 30% sobre o valor total do pedido.']
  ].freeze

  SALE = COMMON.merge(
    'intro' => 'Em atendimento a sua solicitação, segue proposta para fornecimento de equipamento {maquina.marca}',
    'title_prefix' => 'PROPOSTA COMERCIAL',
    'total_label' => 'Total com impostos:',
    'show_discount' => true,
    'show_parties' => false,
    'conditions_style' => 'table',
    'signature_box' => 'Estamos de acordo com as **ESPECIFICAÇÕES TÉCNICAS, CONDIÇÕES COMERCIAIS E PRAZO DE ENTREGA** constantes ' \
                       'nesta proposta e, desta forma, confirmaram a compra dos equipamentos.',
    'conditions' => SALE_CONDITIONS.map { |label, text| { 'label' => label, 'text' => text } }
  ).freeze

  RENTAL = COMMON.merge(
    'intro' => 'Em atendimento a sua solicitação, segue proposta para locação de equipamento {maquina.marca}',
    'title_prefix' => 'PROPOSTA COMERCIAL DE LOCAÇÃO',
    'total_label' => 'Total:',
    'show_discount' => false,
    'show_parties' => true,
    'conditions_style' => 'list',
    'conditions_heading' => 'CONDIÇÕES ESPECIAIS:',
    'parties_text' => 'PROPONENTE: {empresa.razao_social}, pessoa jurídica de direito privado, inscrita no CNPJ sob o nº ' \
                      "{empresa.cnpj}, sediada à {empresa.endereco}.\n\nACEITANTE: {cliente.empresa}, pessoa jurídica de direito " \
                      'privado, inscrita no CNPJ sob o n.º {cliente.documento}, sediada à {cliente.endereco_completo}, representada ' \
                      'pelo(s) seu(s) representante(s) legal(is).',
    'acceptance_text' => 'Ao assinar esta proposta, confirmo que estou ciente e concordo com todas as cláusulas e condições ' \
                         'estabelecidas, sem qualquer discordância ou contestação.',
    'closing' => 'Reiteramos nossos agradecimentos por sua consulta e nos colocamos a disposição para quaisquer informações adicionais.',
    'signature_box' => 'Estamos de acordo com as **ESPECIFICAÇÕES TÉCNICAS, CONDIÇÕES ESPECIAIS E PRAZO DE ENTREGA** constantes ' \
                       'nesta proposta e, desta forma, confirmaram a locação dos equipamentos.',
    'conditions' => RENTAL_CONDITIONS.map { |label, text| { 'label' => label, 'text' => text } }
  ).freeze

  # Cria os dois modelos na primeira vez (conta sem nenhum modelo). O lock da conta evita criar em dobro
  # quando duas telas abrem ao mesmo tempo.
  def ensure!(account)
    return if Outsider::Crm::ProposalTemplate.exists?(account_id: account.id)

    Account.find(account.id).with_lock do
      templates = Outsider::Crm::ProposalTemplate.where(account_id: account.id)
      next if templates.exists?

      templates.create!(name: 'Venda (padrão)', kind: :sale, content: SALE.deep_dup, position: 0)
      templates.create!(name: 'Locação (padrão)', kind: :rental, content: RENTAL.deep_dup, position: 1)
    end
  end
end
