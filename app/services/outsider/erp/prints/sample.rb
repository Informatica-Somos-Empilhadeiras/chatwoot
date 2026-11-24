# OUTSIDER: dados de exemplo para o estúdio de relatórios mostrar o modelo antes de escolher uma OS ou um orçamento de
# verdade. Mesmo formato do Outsider::Erp::ServiceOrderReport / QuoteReport; as fotos são as de public/outsider/erp-prints
# ({ 'sample' => arquivo }) e o logo é o padrão da Somos. Nada aqui acessa o ERP.
# rubocop:disable Metrics/MethodLength
module Outsider::Erp::Prints::Sample
  PHOTOS_DIR = Rails.public_path.join('outsider/erp-prints')
  PHOTOS_URL = '/outsider/erp-prints'.freeze
  PHOTOS = (1..6).map { |number| "amostra-#{number}.jpg" }.freeze

  module_function

  def for(kind) = kind.to_s == 'os' ? service_order : quote

  def photo_path(name) = PHOTOS.include?(name.to_s) ? PHOTOS_DIR.join(name.to_s) : nil

  def logo
    path = Outsider::Erp::Emitter::DEFAULT_LOGO
    File.exist?(path) ? File.binread(path) : nil
  end

  def emitter
    { 'nome' => 'SOMOS EMPILHADEIRAS', 'cnpj' => '52346349000183', 'endereco' => 'Av. Exemplo', 'numero' => '1000',
      'bairro' => 'Centro', 'cidade' => 'Salvador', 'uf' => 'BA', 'fone' => '(71) 3000-0000',
      'email' => 'contato@somosempilhadeiras.com', 'site' => 'somosempilhadeiras.com', 'logo' => logo }
  end

  def photos(*numbers) = numbers.map { |number| { 'sample' => PHOTOS[(number - 1) % PHOTOS.size] } }

  def item(name, arrival, departure, photos = []) = { 'atributo' => name, 'chegada' => arrival, 'saida' => departure, 'fotos' => photos }

  def service_order
    {
      'numero' => 966, 'empresa' => 'somosemp', 'emitente' => emitter,
      'cliente' => { 'nome' => 'LOGÍSTICA ATLÂNTICO LTDA', 'documento' => '12345678000190', 'endereco' => 'Rua das Docas, 450 - Porto',
                     'cidade' => 'Salvador - BA' },
      'equipamento' => { 'descricao' => 'EMPILHADEIRA A COMBUSTÃO 2,5 T', 'marca' => 'HYSTER', 'modelo' => 'H50FT', 'serie' => 'A274B4471',
                         'horimetro' => '12.480' },
      'servico' => { 'tipo_atendimento' => 'MANUT. CORRETIVA', 'classificacao' => 'EXTERNA', 'tecnico' => 'MARCOS SILVA',
                     'defeitos' => 'Vazamento no cilindro de elevação e ruído na bomba hidráulica ao levantar carga acima de 1,5 t.' },
      'avaliacao' => 'Retentor do cilindro de elevação danificado, com vazamento na haste. Bomba hidráulica com folga no eixo. ' \
                     'Substituído o kit de vedação e a bomba; testado com carga nominal, sem vazamentos.',
      'eventos' => [{ 'tipo' => 'Atendimento', 'observacoes' => 'Chegada ao cliente', 'check_in' => '18/11/2026 - 08:10',
                      'check_out' => '18/11/2026 - 11:45' }],
      'produtos' => [{ 'codigo' => '10442', 'descricao' => 'KIT VEDAÇÃO CILINDRO ELEVAÇÃO', 'unidade' => 'UN', 'quantidade' => 1 },
                     { 'codigo' => '20118', 'descricao' => 'BOMBA HIDRÁULICA ENGRENAGEM', 'unidade' => 'UN', 'quantidade' => 1 },
                     { 'codigo' => '30071', 'descricao' => 'ÓLEO HIDRÁULICO ISO 68 (20 L)', 'unidade' => 'BD', 'quantidade' => 2 }],
      'checklist' => [
        { 'nome' => 'Identificação',
          'itens' => [item('Foto da plaqueta', '', '', photos(1, 2, 3)), item('Horímetro', '12.480 h', '12.482 h', photos(4))] },
        { 'nome' => 'Inspeção visual',
          'itens' => [item('Cilindro de elevação', 'Com vazamento', 'OK', photos(5)), item('Pneus', 'Bom', 'Bom', photos(6)),
                      item('Garfos', 'OK', 'OK')] },
        { 'nome' => 'Testes funcionais',
          'itens' => [item('Freio de serviço', 'OK', 'OK'), item('Buzina', 'Não funciona', 'OK'),
                      item('Elevação com carga', 'Ruído na bomba', 'OK', photos(5))] }
      ]
    }
  end

  def quote
    {
      'numero' => 3309, 'data' => Time.zone.today.to_s, 'company' => 'somosemp', 'status' => 'NEGOCIAÇÃO', 'pagamento' => '28/56 DIAS',
      'emitente' => emitter, 'vendedor' => 'ANA SOUZA',
      'cliente' => { 'nome' => 'LOGÍSTICA ATLÂNTICO LTDA', 'documento' => '12345678000190', 'ie' => '123456789', 'endereco' => 'Rua das Docas',
                     'numero' => '450', 'bairro' => 'Porto', 'cidade' => 'Salvador', 'uf' => 'BA', 'cep' => '40000-000',
                     'fone' => '(71) 3333-4444', 'email' => 'compras@atlantico.com.br', 'contato' => 'Rafael', 'fone_contato' => '(71) 99999-0000' },
      'itens' => [
        { 'codigo' => 10_442, 'descricao' => 'KIT VEDAÇÃO CILINDRO ELEVAÇÃO', 'unidade' => 'UN', 'quantidade' => 1, 'unitario' => 890.0,
          'desconto' => 0,
          'total' => 890.0, 'ncm' => '84312011', 'cst' => '000', 'icms' => 18.0, 'vr_icms' => 160.2 },
        { 'codigo' => 20_118, 'descricao' => 'BOMBA HIDRÁULICA ENGRENAGEM', 'unidade' => 'UN', 'quantidade' => 1, 'unitario' => 3450.0,
          'desconto' => 0,
          'total' => 3450.0, 'ncm' => '84136019', 'cst' => '000', 'icms' => 18.0, 'vr_icms' => 621.0 },
        { 'codigo' => 30_071, 'descricao' => 'ÓLEO HIDRÁULICO ISO 68 (20 L)', 'unidade' => 'BD', 'quantidade' => 2, 'unitario' => 310.0,
          'desconto' => 0,
          'total' => 620.0, 'ncm' => '27101932', 'cst' => '000', 'icms' => 18.0, 'vr_icms' => 111.6 }
      ],
      'condicoes' => [['Prazo de Entrega', '5 DIAS ÚTEIS'], ['Validade', '15 DIAS'], ['Prazo de Garantia', '90 DIAS'], ['ICMS', 'INCLUSO']],
      'totais' => [['Sub-Total', 4960.0], ['Desconto', 0], ['Frete', 0]], 'total' => 4960.0,
      'observacoes' => 'Valores válidos para pagamento no prazo combinado. Instalação inclusa.'
    }
  end
end
# rubocop:enable Metrics/MethodLength
