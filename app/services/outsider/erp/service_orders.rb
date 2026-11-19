# OUTSIDER: as ordens de serviço do ERP (espelho, ver Outsider::Erp::Snapshot): as de um cliente, a busca por número ou
# nome e o quadro da página Ordens de serviço (os clientes para vincular vêm do Outsider::Erp::Customers).
#
# Uma OS é a dupla empresa + número: cada empresa do grupo é um banco separado no ERP e os números se repetem entre
# eles. O cliente também (CodigoCliente vale dentro da empresa).
class Outsider::Erp::ServiceOrders
  FIELDS = %w[CodigoOS Empresa CodigoCliente Nome Cidade UF StatusKanban Situacao SubStatus Cor TipoAtendimento TipoOS Classe
              DescricaoMaquina DescricaoFamiliaMaquina NSerie CodigoMaquina PropriedadeMaquina StatusMaquina NomeTecnico NomeVendedor
              NomeAtendente DataEntrada DataPrevisao DataEntrega DtUltimoStatus DiasAtraso QtdProduto QtdServico Observacoes Defeitos
              Acessorios DataValidade EnviadoMobile].freeze
  UNDEFINED = 'NÃO DEFINIDO'.freeze
  BOARD_LIMIT = 150

  def initialize(account)
    @account = account
    @settings = Outsider::Erp::Settings.new(account)
  end

  attr_reader :settings

  def snapshot
    @snapshot ||= Outsider::Erp::Snapshot.new(@account, 'os', ttl: settings.data['cache_seconds'], loader: method(:load))
  end

  def fetch
    @fetch ||= snapshot.fetch
  end

  def items = fetch['items']
  def meta = { fetched_at: Time.zone.at(fetch['at']).iso8601, stale: fetch['stale'] }

  def find(company, code)
    items.find { |item| item['Empresa'] == company && item['CodigoOS'].to_i == code.to_i }
  end

  # links: [{ 'empresa' =>, 'codigo' => }] (Outsider::Erp::ContactLink)
  def for_clients(links)
    wanted = links.to_set { |link| [link['empresa'], link['codigo'].to_i] }
    sort(items.select { |item| wanted.include?([item['Empresa'], item['CodigoCliente'].to_i]) })
  end

  # número da OS ou parte do nome do cliente / da máquina / do número de série
  def search(query, limit: 30)
    query = query.to_s.strip
    return [] if query.length < 2
    return sort(items.select { |item| item['CodigoOS'].to_s == query }) if query.match?(/\A\d+\z/)

    words = self.class.words(query)
    sort(items.select { |item| self.class.matches?(words, "#{item['Nome']} #{item['DescricaoMaquina']} #{item['NSerie']}") }).first(limit)
  end

  # substatus que dá para escolher numa OS: os da lista das Configurações ou, sem lista, os que já aparecem nas OS da
  # mesma empresa (os nomes mudam por filial, ex.: "2-AGENDADO (DF)")
  def substatus_options(company)
    configured = Array(settings.data['substatus_options'])
    return configured if configured.any?

    items.select { |item| item['Empresa'] == company }.filter_map { |item| item['SubStatus'].presence }.uniq.sort_by { |value| substatus_sort(value) }
  end

  # quadro: colunas pelo substatus (sem o sufixo da filial) ou pela situação do kanban do ERP
  def board(group_by: 'substatus', company: nil, technician: nil, query: nil)
    list = filtered(company: company, technician: technician, query: query)
    columns = list.group_by { |item| column_for(item, group_by) }
    {
      columns: columns.sort_by { |name, _| substatus_sort(name) }.map do |name, orders|
        { name: name, count: orders.size, orders: sort(orders).first(BOARD_LIMIT) }
      end,
      companies: items.filter_map { |item| item['Empresa'] }.uniq.sort,
      technicians: items.filter_map { |item| item['NomeTecnico'].presence }.uniq.sort,
      total: list.size
    }
  end

  def self.words(text)
    normalize(text).split.reject { |word| word.length < 2 || %w[LTDA ME EPP SA EIRELI DE DA DO DOS DAS E].include?(word) }
  end

  def self.matches?(words, text)
    target = normalize(text)
    words.any? && words.all? { |word| target.include?(word) }
  end

  def self.normalize(text)
    I18n.transliterate(text.to_s).upcase.gsub(/[^A-Z0-9 ]/, ' ').squish
  end

  private

  def load(read_timeout)
    extra = settings.writable_fields.keys
    Outsider::Erp::Client.new(settings).service_orders(read_timeout: read_timeout).map { |item| item.slice(*(FIELDS | extra)) }
  end

  def filtered(company:, technician:, query:)
    list = query.present? ? search(query, limit: items.size) : items
    list = list.select { |item| item['Empresa'] == company } if company.present?
    list = list.select { |item| item['NomeTecnico'] == technician } if technician.present?
    list
  end

  def column_for(item, group_by)
    group_by == 'status' ? item['StatusKanban'].presence || UNDEFINED : substatus_group(item['SubStatus'])
  end

  def sort(list)
    list.sort_by { |item| item['DataEntrada'].to_s }.reverse
  end

  def substatus_group(value)
    value = value.to_s.sub(/\s*\([A-Z]{2}\)\z/, '').sub(/\A(\d+)\s*-\s*/, '\1-').strip
    value.presence || UNDEFINED
  end

  # "1-AGENDAR", "2-AGENDADO"... pela ordem do número; sem número por último
  def substatus_sort(value)
    number = value.to_s[/\A\s*(\d+)/, 1]
    [number ? 0 : 1, number.to_i, value.to_s]
  end
end
