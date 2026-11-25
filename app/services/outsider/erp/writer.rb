# OUTSIDER: grava no ERP um campo de uma OS que já existe. Só com a escrita ligada nas Configurações, só nos endpoints
# confirmados (Outsider::Erp::Settings#writable_fields) e só numa OS que está no espelho: a empresa da gravação é a da
# própria OS, nunca a que veio da tela. Substatus e situação fazem o mesmo par de chamadas do painel do ERP (troca +
# histórico), para o histórico de lá continuar certo; situação e tipo de atendimento só aceitam valores das listas do
# próprio ERP (Outsider::Erp::Lists). Criar ou apagar OS não existe na API web (só no sistema desktop).
class Outsider::Erp::Writer
  class Invalid < StandardError; end
  class Disabled < StandardError; end
  class Locked < StandardError; end

  MAX_TEXT = 4000
  DATE = /\A\d{4}-\d{2}-\d{2}\z/

  def initialize(account:, user:)
    @account = account
    @user = user
    @orders = Outsider::Erp::ServiceOrders.new(account)
    @settings = @orders.settings
    @client = Outsider::Erp::Client.new(@settings)
  end

  def substatus(company:, code:, value:, conversation: nil)
    order = writable_order(company, code)
    value = value.to_s.squish
    raise Invalid, 'value' unless substatus_options(order['Empresa']).include?(value)

    previous = order['SubStatus'].to_s
    return order if previous == value

    @client.update('UpdateSubStatusOS', order['CodigoOS'], body(order, 'SubStatus' => value))
    @client.update('GravaHistoricoSubStatusOS', order['CodigoOS'],
                   body(order, 'SubStatusAntigo' => previous.presence || value, 'SubStatusNovo' => value, 'idUsuario' => erp_user))
    changed(order, 'SubStatus', previous, value, conversation)
  end

  # situação (status) da OS: troca + grava o histórico, igual ao painel (as opções vêm de ListaStatusOS)
  def status(company:, code:, value:, conversation: nil)
    order = writable_order(company, code)
    value = listed(lists.statuses, value)
    previous = order['Situacao'].to_s
    return order if previous == value

    @client.update('UpdateStatusOS', order['CodigoOS'], body(order, 'Situacao' => value))
    @client.update('GravaHistoricoStatusOS', order['CodigoOS'], body(order, 'Situacao' => value, 'idUsuario' => erp_user))
    changed(order, 'Situacao', previous, value, conversation)
  end

  # tipo de atendimento da OS (as opções vêm de ListaTipoAtendimento)
  def attendance_type(company:, code:, value:, conversation: nil)
    order = writable_order(company, code)
    value = listed(lists.attendance_types, value)
    previous = order['TipoAtendimento'].to_s
    return order if previous == value

    @client.update('UpdateTipoAtendimento', order['CodigoOS'], body(order, 'TipoAtendimentoAtual' => value))
    changed(order, 'TipoAtendimento', previous, value, conversation)
  end

  # técnico da OS: manda o código (as opções vêm de ListaTecnicos); o nome só alimenta o espelho
  def technician(company:, code:, tecnico_id:, tecnico_name: nil, conversation: nil)
    order = writable_order(company, code)
    tecnico_id = Integer(tecnico_id)

    @client.update('UpdateTecnico', order['CodigoOS'], body(order, 'TecnicoAtual' => tecnico_id))
    changed(order, 'NomeTecnico', order['NomeTecnico'].to_s, tecnico_name.to_s.presence || tecnico_id.to_s, conversation)
  rescue ArgumentError, TypeError
    raise Invalid, 'tecnico'
  end

  # os substatus que valem para a OS (Configurações, ERP e espelho): o agendamento procura o "AGENDADO" da filial aqui
  def substatus_choices(company) = substatus_options(company)

  # campos simples (texto ou data) liberados nas Configurações; data vai como AAAA-MM-DD
  def field(company:, code:, field:, value:, conversation: nil)
    order = writable_order(company, code)
    field = field.to_s
    endpoint = @settings.writable_fields[field]
    raise Invalid, 'field' unless endpoint

    value = clean_value(field, value)
    previous = order[field].to_s
    return order if previous == value

    @client.update(endpoint, order['CodigoOS'], body(order, field => value))
    changed(order, field, previous, value, conversation)
  end

  private

  def writable_order(company, code)
    raise Disabled unless @settings.write_enabled?

    order = current_order(company.to_s, code)
    raise Invalid, 'order' unless order && @settings.companies.include?(order['Empresa'])
    raise Locked, order['Situacao'].to_s if @settings.locked_statuses.include?(order['Situacao'].to_s.strip.upcase)

    order
  end

  # OS como está agora no banco do ERP (situação fresca para a trava e OS fora da janela do espelho); sem resposta do
  # banco, a do espelho
  def current_order(company, code)
    return @orders.find(company, code) unless @settings.companies.include?(company)

    records.editor_for(company, code)
  rescue Outsider::Erp::Records::Detail::NotFound, Outsider::Erp::Client::Error
    @orders.find(company, code)
  end

  def records = @records ||= Outsider::Erp::Records::Detail.new(@account, 'orders', client: @client)

  # corpo padrão das rotas do Kanban: o campo + as empresas do grupo + a empresa da própria OS
  def body(order, fields)
    fields.merge('listaEmpresas' => @settings.companies, 'Empresa' => order['Empresa'])
  end

  def lists = @lists ||= Outsider::Erp::Lists.new(@account)

  def substatus_options(company)
    @orders.substatus_options(company) | records.substatus_options(company)
  rescue Outsider::Erp::Client::Error
    @orders.substatus_options(company)
  end

  def erp_user = @settings.erp_user_id_for(@user)

  def listed(options, value)
    value = value.to_s.squish
    raise Invalid, 'value' unless value.present? && options.include?(value)

    value
  end

  def clean_value(field, value)
    value = value.to_s.strip
    raise Invalid, 'value' if value.length > MAX_TEXT
    raise Invalid, 'value' if Outsider::Erp::Settings::FIELD_KINDS[field] == 'date' && value.present? && !value.match?(DATE)

    value
  end

  def changed(order, field, previous, value, conversation)
    updated = order.merge(field => value)
    @orders.snapshot.patch { |item| updated if item['Empresa'] == order['Empresa'] && item['CodigoOS'] == order['CodigoOS'] }
    if conversation && @settings.data['note_on_change']
      Outsider::Erp::ChangeNote.new(user: @user, conversation: conversation).post(order: order, field: field, from: previous, to: value)
    end
    Rails.logger.info("[Outsider::Erp] conta #{@account.id} usuário #{@user.id} OS #{order['Empresa']}/#{order['CodigoOS']} #{field} alterado")
    updated
  end
end
