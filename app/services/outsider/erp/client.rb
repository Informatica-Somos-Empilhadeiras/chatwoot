# OUTSIDER: chamadas à API web do ERP Mais Prático (ver Outsider::Erp::Settings para as regras). Só os caminhos daqui:
# leitura das OS (KanbanOrdemServico/valoresDash), do relatório de uma OS com as fotos do checklist (Dados*_PDF e
# getimagemchecklistos, os mesmos do kanban de KPI), dos orçamentos (cotacaoDesempenho/valoresDash) e a gravação de campos
# de uma OS que já existe (PUT KanbanOrdemServico/Update<Campo>/<OS>). Nós nos identificamos (User-Agent próprio) e
# nunca disparamos gravação de teste: quem chama já conferiu a OS, a empresa e o campo.
class Outsider::Erp::Client
  class Error < StandardError; end
  class TooLarge < Error; end

  USER_AGENT = 'Chatwoot-Somos/1.0 (integracao ERP; ordens de servico)'.freeze
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 25
  WRITE_TIMEOUT = 15
  MAX_BYTES = 40.megabytes
  OS_PATH = '/KanbanOrdemServico/api/valoresDash'.freeze
  QUOTES_PATH = '/cotacaoDesempenho/api/valoresDash'.freeze
  UPDATE_PATH = '/KanbanOrdemServico/api/%<endpoint>s/%<code>d'.freeze
  KANBAN_LIST_PATH = '/KanbanOrdemServico/api/%<endpoint>s'.freeze
  PHOTO_PATH = '/KanbanOrdemServico/api/getimagemchecklistos/%<ref>s/%<company>s'.freeze
  QUERY_PATH = '/dashboard/api/query_execute'.freeze

  def initialize(settings)
    @settings = settings
  end

  # mesmos parâmetros do quadro de OS do painel web deles
  def service_orders(read_timeout: READ_TIMEOUT)
    today = Time.zone.today
    query = companies_query(@settings.companies) + [
      %w[idUsuario 0], %w[respeitarRegrasHierarquia 1], ['diasPrevisao', @settings.data['forward_days'].to_s],
      ['vDataInicial', (today - @settings.data['lookback_days'].days).iso8601],
      ['vDataFinal', (today + @settings.data['forward_days'].days).iso8601], ['myTipoData', @settings.data['date_type']]
    ]
    list(get(OS_PATH, query, read_timeout))
  end

  # a tela de orçamentos deles pede uma empresa por vez; a resposta traz o CNPJ, não o nome do banco
  def quotes(company, read_timeout: READ_TIMEOUT)
    today = Time.zone.today
    query = [%w[tipoData OrcamentoData], ['dataCadastroInicio', (today - @settings.data['quotes_days'].days).iso8601],
             ['dataCadastroFim', (today + 1.day).iso8601]] + companies_query([company]) +
            [%w[idUsuario 0], %w[respeitarRegrasHierarquia 0]]
    list(get(QUOTES_PATH, query, read_timeout))
  end

  def update(endpoint, code, body)
    path = format(UPDATE_PATH, endpoint: endpoint, code: Integer(code))
    response = HTTParty.put("#{@settings.base_url}#{path}", body: body.to_json, open_timeout: OPEN_TIMEOUT, read_timeout: WRITE_TIMEOUT,
                                                            headers: headers.merge('Content-Type' => 'application/json;charset=UTF-8'))
    raise Error, "HTTP #{response.code}" unless response.code == 200

    true
  rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, EOFError, OpenSSL::SSL::SSLError => e
    raise Error, e.class.name
  end

  # listas do Kanban sem código de OS: ListaStatusOS, ListaTecnicos, ListaTipoAtendimento (mesmos parâmetros do painel)
  def kanban_list(endpoint, read_timeout: READ_TIMEOUT)
    list(get(format(KANBAN_LIST_PATH, endpoint: endpoint), companies_query(@settings.companies), read_timeout))
  end

  # uma parte do relatório de uma OS (o mesmo que o kanban de KPI deles imprime): DadosOS_PDF, DadosCheckIn_PDF,
  # DadosCheckList_PDF, DadosProdutosOS_PDF
  def service_order_report(endpoint, company, code, read_timeout: READ_TIMEOUT)
    list(get(format(KANBAN_LIST_PATH, endpoint: endpoint), [['CodigoOS', Integer(code)], ['Empresa', company]], read_timeout))
  end

  # foto do checklist de uma OS (ref = CaminhoIMG, "<OS>_<n>"), em bytes; quem desenha confere o formato
  def checklist_photo(company, ref, read_timeout: READ_TIMEOUT)
    get(format(PHOTO_PATH, ref: ref, company: ERB::Util.url_encode(company)), [], read_timeout, accept: 'image/*').b
  end

  # rota liberada pela Inntegra para a Somos: roda a SQL do lado do servidor (ver Outsider::Erp::Sql para a montagem
  # segura, e Outsider::Erp::QuoteCreator para o uso). Só quem chama monta a SQL; aqui só transporta e devolve o JSON.
  def query_execute(sql, read_timeout: WRITE_TIMEOUT)
    response = HTTParty.put("#{@settings.base_url}#{QUERY_PATH}", body: { SQL_Execute: sql }.to_json,
                                                                  open_timeout: OPEN_TIMEOUT, read_timeout: read_timeout,
                                                                  headers: headers.merge('Content-Type' => 'application/json;charset=UTF-8'))
    raise Error, "HTTP #{response.code}" unless response.code == 200

    parse(response.body)
  rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, EOFError, OpenSSL::SSL::SSLError => e
    raise Error, e.class.name
  end

  private

  def companies_query(companies)
    companies.map { |company| ['listaEmpresas[]', company] }
  end

  def headers(accept = 'application/json')
    { 'Accept' => accept, 'User-Agent' => USER_AGENT }.merge(@settings.device_id.present? ? { 'x-device-id' => @settings.device_id } : {})
  end

  def get(path, query, read_timeout, accept: 'application/json')
    body = +''
    url = "#{@settings.base_url}#{path}"
    url += "?#{URI.encode_www_form(query)}" if query.any?
    response = HTTParty.get(url, headers: headers(accept), open_timeout: OPEN_TIMEOUT, read_timeout: read_timeout, stream_body: true) do |fragment|
      next unless fragment.code == 200

      body << fragment
      raise TooLarge if body.bytesize > MAX_BYTES
    end
    raise Error, "HTTP #{response.code}" unless response.code == 200

    body
  rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, EOFError, OpenSSL::SSL::SSLError => e
    raise Error, e.class.name
  end

  def list(body)
    data = parse(body)
    raise Error, 'resposta sem lista' unless data.is_a?(Array)

    data.grep(Hash)
  end

  def parse(body)
    JSON.parse(body)
  rescue JSON::ParserError
    raise Error, 'resposta não é JSON'
  end
end
