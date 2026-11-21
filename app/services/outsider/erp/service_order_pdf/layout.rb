# OUTSIDER: as medidas do relatório da OS, tiradas do PDF que o kanban de KPI do Mais Prático emite (OS 850), em
# pontos e contadas do topo da página. Parte do Outsider::Erp::ServiceOrderPdf.
module Outsider::Erp::ServiceOrderPdf::Layout
  PAGE_HEIGHT = 841.89
  LEFT = 24.96
  RIGHT = 571.92
  CENTER = (LEFT + RIGHT) / 2
  BOTTOM = 830.4 # o original imprime até 829,80 (fim da tabela de produtos da OS 850)
  BORDER = 0.84
  LINE = 11.28 # entre linhas de base no texto de 10pt
  EVALUATION_LINE = 11.272 # na avaliação técnica (15 intervalos somam 169,08 no original)
  TEXT = '333333'.freeze
  BLUE = '005596'.freeze
  LABEL = '02487E'.freeze
  MUTED = 'ABABAB'.freeze
  GRID = 'CCCCCC'.freeze

  # campos: [x, largura de quebra]; na linha da cidade, o nº de série e o horímetro dividem a coluna da direita
  COLUMNS = [[28.8, 244.48], [280.96, 287.12]].freeze
  COLUMNS_WITH_HOURS = [[28.8, 244.48], [280.96, 121.84], [410.48, 157.6]].freeze
  FULL_ROW = [[28.8, 539.28]].freeze

  # tabelas: x das bordas verticais (a última é a borda direita) e o alinhamento de cada coluna
  EVENTS = { caption: 'Eventos (check-in/out)', heads: %w[Evento Observações Check-In Check-Out],
             borders: [24.96, 218.04, 310.32, 440.28, 571.08], aligns: %i[left center center center] }.freeze
  PRODUCTS = { caption: 'Produtos / serviços', heads: %w[Código Descrição Unidade Qtd],
               borders: [24.96, 77.52, 480.24, 538.68, 571.08], aligns: %i[center left center center] }.freeze

  # checklist: nome do item e leitura (CHEGADA/SAÍDA) lado a lado; fotos em 4 colunas, largura fixa e altura natural
  ITEM_X = 34.75
  READING_X = 302.94
  ITEM_WIDTH = 268.19
  PHOTO_X = [27.96, 166.08, 303.6, 441.84].freeze
  PHOTO_WIDTH = 127.34
  PHOTO_GAP = 23.28
  # da linha de base do nome da seção, por o que veio antes (cabeçalho da página ou fotos); o resto, 24
  SECTION_GAP = { header: 24.72, photos: 33.84 }.freeze
end
