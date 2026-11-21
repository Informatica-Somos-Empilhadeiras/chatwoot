# OUTSIDER: lê do ERP tudo que o relatório de uma OS precisa, no modelo da "Impressão de Ordem de Serviço - Check-List"
# do kanban de KPI deles (OS 850): emitente, cliente e equipamento, serviço, check-in/out, avaliação técnica, produtos e
# o checklist com as fotos. Só leitura (GET), pelo banco e pelo número da OS. Devolve o hash que o
# Outsider::Erp::ServiceOrderPdf desenha, com as fotos já em bytes.
class Outsider::Erp::ServiceOrderReport
  class NotFound < StandardError; end

  # foto do checklist: "<OS>_<n>" (campo CaminhoIMG). O temImg vem 0 mesmo quando a foto existe, então não serve de filtro.
  PHOTO_REF = /\A\d+_\d+\z/

  def initialize(account, client: nil)
    @account = account
    @client = client || Outsider::Erp::Client.new(Outsider::Erp::Settings.new(account))
  end

  def build(company, code)
    order = part('DadosOS_PDF', company, code).first
    raise NotFound unless order

    {
      'numero' => code.to_i, 'empresa' => company, 'emitente' => emitter(order),
      'cliente' => customer(order), 'equipamento' => equipment(order), 'servico' => service(order),
      'avaliacao' => text(order['AvaliacaoTecnica']),
      'eventos' => part('DadosCheckIn_PDF', company, code).map { |row| event(row) },
      'produtos' => part('DadosProdutosOS_PDF', company, code).map { |row| product(row) },
      'checklist' => sections(company, code, part('DadosCheckList_PDF', company, code))
    }
  end

  private

  def part(endpoint, company, code) = @client.service_order_report(endpoint, company, code)

  def text(value) = value.to_s.strip

  def joined(*values) = values.map { |value| text(value) }.compact_blank.join(' - ')

  # o cabeçalho do relatório deles vem da própria OS (colunas *Impressao) e o logo do CNPJ do emitente
  def emitter(row)
    { 'nome' => text(row['NomeImpressao']), 'fone' => text(row['TelefoneImpressao']), 'email' => text(row['EmailImpressao']),
      'logo' => image(-> { @client.company_logo(row['CPF_CNPJ']) }) }
  end

  def customer(row)
    { 'nome' => text(row['NomeCliente']), 'documento' => text(row['CPF_CNPJCliente']),
      'endereco' => joined(row['endereco'], row['bairro']), 'cidade' => joined(row['cidade'], row['uf']) }
  end

  def equipment(row)
    { 'descricao' => text(row['DescricaoMaquina']), 'marca' => text(row['marca']), 'modelo' => text(row['modelo']),
      'serie' => text(row['nserie']), 'horimetro' => text(row['Horimetro']) }
  end

  def service(row)
    { 'tipo_atendimento' => text(row['TipoAtendimento']), 'classificacao' => text(row['ClasseOS']),
      'tecnico' => text(row['NomeTecnico']), 'defeitos' => text(row['Defeitos']) }
  end

  # o ERP já manda a data/hora formatada ("11/11/2026 - 07:20")
  def event(row)
    { 'tipo' => text(row['Tipo']), 'observacoes' => text(row['Observacoes']),
      'check_in' => text(row['dataHoraCheckIn']), 'check_out' => text(row['dataHoraCheckOut']) }
  end

  def product(row)
    { 'codigo' => text(row['CodigoProduto']), 'descricao' => text(row['Descricao']), 'unidade' => text(row['Unidade']),
      'quantidade' => row['Quantidade'] }
  end

  # cada linha do checklist é uma foto ligada a um item; agrupa seção > item na ordem do ERP
  def sections(company, code, rows)
    sorted = rows.sort_by { |row| [row['ORDEM_SESSAO'].to_i, row['ORDEM_ATRIBUTO'].to_i, row['CodigoAnexo'].to_i] }
    photos = photos_for(company, code, sorted.map { |row| text(row['CaminhoIMG']) })
    sorted.group_by { |row| row['COD_SESSAO'] }.values.map do |section_rows|
      { 'nome' => text(section_rows.first['DESC_SESSAO']),
        'itens' => section_rows.group_by { |row| row['COD_ATRIBUTO'] }.values.map { |item_rows| item(item_rows, photos) } }
    end
  end

  def item(rows, photos)
    first = rows.first
    { 'atributo' => text(first['DESC_ATRIBUTO']), 'chegada' => reading(first, first['VALOR_INI'].presence || first['VALOR']),
      'saida' => reading(first, first['VALOR_FIM']), 'fotos' => rows.filter_map { |row| photos[text(row['CaminhoIMG'])] } }
  end

  # VALOR_INI é a leitura na chegada e VALOR_FIM na saída; PREFIXO/SUFIXO envolvem o valor
  def reading(row, value)
    return '' if text(value).blank?

    [row['PREFIXO'], value, row['SUFIXO']].map { |part| text(part) }.compact_blank.join(' ')
  end

  # só as fotos desta OS, em JPEG/PNG (o que o Prawn desenha); a que faltar no ERP fica de fora e o relatório sai assim mesmo
  def photos_for(company, code, refs)
    refs.uniq.select { |ref| ref.match?(PHOTO_REF) && ref.start_with?("#{code.to_i}_") }
        .index_with { |ref| image(-> { @client.checklist_photo(company, ref) }) }.compact
  end

  # imagem do ERP só se vier JPEG/PNG (o que o Prawn desenha); a que faltar fica de fora e o relatório sai assim mesmo
  def image(fetch)
    bytes = fetch.call
    bytes if bytes.start_with?("\xFF\xD8".b, "\x89PNG".b)
  rescue Outsider::Erp::Client::Error
    nil
  end
end
