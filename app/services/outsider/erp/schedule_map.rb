# OUTSIDER: "Mapa dos agendamentos" (Aplicativos > Google): os clientes com OS agendada no período, um ponto por cliente.
# Agendadas = as marcadas pelo Agendar do Chatwoot (Outsider::Erp::OrderSchedule) e as OS do espelho do ERP com
# substatus AGENDADO e previsão no período (marcadas no próprio Mais Prático).
# O ponto do cliente, nesta ordem: o local exato escolhido no agendamento, o local principal de um contato ligado ao
# cliente (Outsider::ContactPlace) e, por último, o endereço do cadastro do ERP procurado no mapa (Outsider::Geocoder,
# aproximado; guardado 30 dias). Poucas buscas de endereço por chamada (o serviço gratuito aceita uma por segundo): a tela
# pede de novo enquanto faltar (pending).
# client: a ficha do lado (cadastro do ERP com os vazios completados pela consulta do CNPJ, só na tela), os contatos (do
# chat e do cadastro do ERP), as máquinas no cliente e as OS abertas. Só leitura.
class Outsider::Erp::ScheduleMap
  S = Outsider::Erp::Sql
  MAX_SCHEDULES = 400
  GEOCODE_PER_CALL = 6
  GEO_TTL = 30.days
  RECORD_TTL = 1.day
  CLOSED = /CONCLU|CANCEL|FECHAD|FINALIZ|ENCERR|PERDID/i
  # campo do cadastro do ERP => campo da consulta do CNPJ (Outsider::Crm::CompanyLookup)
  LOOKUP = { 'nome' => :company, 'fantasia' => :trade_name, 'ie' => :state_registration, 'endereco' => :street,
             'numero' => :number, 'complemento' => :complement, 'bairro' => :district, 'cidade' => :city, 'uf' => :state,
             'cep' => :zip, 'fone' => :phone, 'email' => :email }.freeze
  ERP_CONTACT = { 'nome' => %w[Nome], 'fone' => %w[Fone Telefone], 'email' => %w[Email], 'cargo' => %w[Cargo Funcao Departamento] }.freeze

  def initialize(account)
    @account = account
    @settings = Outsider::Erp::Settings.new(account)
    @orders = Outsider::Erp::ServiceOrders.new(account)
  end

  # from/to: Time; technician: nome do técnico (como no espelho) ou nil
  # => { clients: [{ company, code, name, city, latitude, longitude, approximate, source, schedules: [...] }],
  #      missing: [clientes sem ponto ainda], pending: n, technicians: [...] }
  def points(from:, to:, technician: nil)
    rows = chatwoot_rows(from, to) + erp_rows(from, to)
    technicians = rows.filter_map { |row| row[:technician].presence }.uniq.sort
    rows = rows.select { |row| row[:technician].to_s == technician.to_s } if technician.present?
    @budget = GEOCODE_PER_CALL
    clients = rows.group_by { |row| [row[:company], row[:client_code]] }.map do |(company, code), list|
      client_json(company, code, list, point_for(company, code, list) || geocoded(company, code))
    end
    { clients: clients.select { |row| row[:latitude] }, missing: clients.reject { |row| row[:latitude] },
      pending: clients.count { |row| row[:latitude].nil? && row[:geocode] != 'failed' }, technicians: technicians }
  end

  def client(company, code)
    raise ArgumentError, 'empresa' unless @settings.companies.include?(company.to_s)

    record = record(company, code)
    links = [{ 'empresa' => company.to_s, 'codigo' => code.to_i }]
    {
      company: company, code: code.to_i, unit: @settings.company_names[company].presence || company, record: record, completed: completed(record),
      contacts: Outsider::Erp::Records::ContactFinder.new(@account).for_client(company, code)['contacts'],
      erp_contacts: erp_contacts(company, code), machines: machines(links),
      orders: @orders.for_clients(links).reject { |item| closed?(item) }.first(30).map { |item| order_json(item) }
    }
  end

  private

  def chatwoot_rows(from, to)
    Outsider::Erp::OrderSchedule.where(account_id: @account.id, starts_at: from..to).order(:starts_at).limit(MAX_SCHEDULES).filter_map do |item|
      order = @orders.find(item.company, item.order_number)
      next unless order

      { company: item.company, client_code: order['CodigoCliente'].to_i, order: item.order_number, client: order['Nome'],
        start: local(item, item.starts_at), end: local(item, item.ends_at), all_day: item.all_day, title: item.title,
        technician: order['NomeTecnico'], status: order['Situacao'], substatus: order['SubStatus'], kind: order['TipoAtendimento'],
        machine: order['DescricaoMaquina'], city: [order['Cidade'], order['UF']].compact_blank.join(' - '), source: 'chatwoot',
        point: item.latitude && { latitude: item.latitude.to_f, longitude: item.longitude.to_f, name: item.place_name } }
    end
  end

  # OS agendadas no Mais Prático (substatus AGENDADO) com a previsão no período, fora as que o Chatwoot já agendou
  def erp_rows(from, to)
    marked = Outsider::Erp::OrderSchedule.where(account_id: @account.id).pluck(:company, :order_number).to_set
    @orders.items.filter_map do |order|
      next unless scheduled?(order) && marked.exclude?([order['Empresa'], order['CodigoOS'].to_i])

      day = date(order['DataPrevisao'])
      next unless day && day >= from.to_date && day <= to.to_date

      { company: order['Empresa'], client_code: order['CodigoCliente'].to_i, order: order['CodigoOS'].to_i, client: order['Nome'],
        start: "#{day.iso8601}T00:00:00", end: nil, all_day: true, title: nil, technician: order['NomeTecnico'],
        status: order['Situacao'], substatus: order['SubStatus'], kind: order['TipoAtendimento'], machine: order['DescricaoMaquina'],
        city: [order['Cidade'], order['UF']].compact_blank.join(' - '), source: 'erp', point: nil }
    end
  end

  def scheduled?(order)
    Outsider::Erp::ServiceOrders.normalize(order['SubStatus'].to_s).include?('AGENDADO') && !closed?(order)
  end

  def closed?(order) = [order['Situacao'], order['SubStatus'], order['StatusKanban']].any? { |value| value.to_s.match?(CLOSED) }

  def date(value)
    Date.parse(value.to_s.first(10))
  rescue ArgumentError, TypeError
    nil
  end

  def local(schedule, time)
    zone = ActiveSupport::TimeZone[schedule.time_zone.to_s] || ActiveSupport::TimeZone['America/Sao_Paulo']
    time.in_time_zone(zone).strftime('%Y-%m-%dT%H:%M:%S')
  end

  # o local exato do agendamento mais recente, ou o local principal de um contato ligado ao cliente
  def point_for(company, code, list)
    exact = list.reverse.find { |row| row[:point] }&.dig(:point)
    return exact.merge(approximate: false, source: 'schedule') if exact

    contact_ids = Outsider::Erp::Records::ContactFinder.new(@account).for_client(company, code)['contacts'].pluck('id')
    place = Outsider::ContactPlace.where(account_id: @account.id, contact_id: contact_ids).order(main: :desc, created_at: :asc).first
    place && { latitude: place.latitude.to_f, longitude: place.longitude.to_f, name: place.name, approximate: false, source: 'contact' }
  end

  # o endereço do cadastro do ERP no mapa (aproximado: o serviço costuma achar a rua). Guardado 30 dias, também quando
  # não acha (para não procurar de novo a cada abertura).
  # Só GEOCODE_PER_CALL buscas novas por chamada; o que já foi achado (ou não) vem do cache.
  def geocoded(company, code)
    cache_key = "outsider_erp_map_geo/v1/#{@account.id}/#{company}/#{code}"
    cached = Rails.cache.read(cache_key)
    return cached if cached
    return nil unless @budget.positive?

    @budget -= 1
    address = address_of(record(company, code))
    found = address.present? && Outsider::Geocoder.new.search(address).first
    result = if found
               { latitude: found[:latitude], longitude: found[:longitude], approximate: !found[:exact], source: 'address' }
             else
               { geocode: 'failed' }
             end
    Rails.cache.write(cache_key, result, expires_in: GEO_TTL)
    result
  rescue Outsider::Geocoder::Error, Outsider::Erp::Client::Error => e
    Rails.logger.info("[Outsider::Erp] mapa: endereço do cliente #{company}/#{code} não achado: #{e.message}")
    nil
  end

  def address_of(record)
    street = [record['endereco'], record['numero']].compact_blank.join(', ')
    [street, record['bairro'], record['cidade'], record['uf']].compact_blank.join(', ').presence
  end

  def client_json(company, code, list, point)
    point = point.is_a?(Hash) ? point : {}
    first = list.first
    { company: company, code: code, name: first[:client], city: first[:city], unit: @settings.company_names[company].presence || company,
      latitude: point[:latitude], longitude: point[:longitude], approximate: point[:approximate], source: point[:source],
      place_name: point[:name], geocode: point[:geocode],
      schedules: list.sort_by { |row| row[:start].to_s }.map { |row| row.except(:point, :company, :client_code, :client, :city) } }
  end

  def record(company, code)
    Rails.cache.fetch("outsider_erp_map_record/v1/#{@account.id}/#{company}/#{code}", expires_in: RECORD_TTL) do
      Outsider::Erp::CustomerRecord.new(@account, client: erp_client).find(company, code)
    end
  end

  # os campos vazios no cadastro do ERP que a consulta do CNPJ conhece (só para mostrar; nada é gravado no ERP)
  def completed(record)
    document = record['documento'].to_s.gsub(/[^0-9A-Za-z]/, '')
    return {} unless document.length == 14

    customer = Outsider::Crm::CompanyLookup.new(document).perform[:customer].to_h.symbolize_keys
    LOOKUP.each_with_object({}) do |(field, key), found|
      found[field] = customer[key] if record[field].blank? && customer[key].present?
    end
  rescue StandardError => e # a consulta é um extra: sem ela a ficha aparece só com o cadastro do ERP
    Rails.logger.info("[Outsider::Erp] mapa: consulta do CNPJ falhou: #{e.class} #{e.message}")
    {}
  end

  def erp_contacts(company, code)
    schema = Outsider::Erp::Schema.new(@account, client: erp_client)
    return [] unless schema.pick(company, 'contatosclientes', %w[CodigoCliente])

    sql = "SELECT #{schema.select_list(company, 'contatosclientes', 'K', ERP_CONTACT)} FROM #{S.ident(company)}.contatosclientes K " \
          "WHERE K.`CodigoCliente` = #{S.int(code)} LIMIT 20"
    erp_client.query_execute(sql).grep(Hash).map { |row| row.transform_values { |value| value.is_a?(String) ? value.squish.presence : value } }
              .select { |row| row['nome'].present? || row['fone'].present? || row['email'].present? }
  rescue Outsider::Erp::Client::Error
    []
  end

  def machines(links)
    summary = Outsider::Erp::Rentals::ClientSummary.new(@account, client: erp_client).build(links)
    rented = summary['contracts'].flat_map do |contract|
      contract['maquinas'].map do |machine|
        machine.merge('kind' => 'rented', 'contrato' => contract['numero'], 'contrato_status' => contract['status'])
      end
    end
    rented + summary['machines'].map { |machine| machine.merge('kind' => 'own') }
  rescue Outsider::Erp::Client::Error
    []
  end

  def order_json(item)
    { company: item['Empresa'], code: item['CodigoOS'].to_i, status: item['Situacao'], substatus: item['SubStatus'],
      kind: item['TipoAtendimento'], machine: item['DescricaoMaquina'], serie: item['NSerie'], technician: item['NomeTecnico'],
      forecast: item['DataPrevisao'], entered: item['DataEntrada'], defects: item['Defeitos'] }
  end

  def erp_client
    @erp_client ||= Outsider::Erp::Client.new(@settings)
  end
end
