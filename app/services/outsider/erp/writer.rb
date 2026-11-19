# OUTSIDER: grava no ERP um campo de uma OS que já existe. Só com a escrita ligada nas Configurações, só nos endpoints
# confirmados (Outsider::Erp::Settings#writable_fields) e só numa OS que está no espelho: a empresa da gravação é a da
# própria OS, nunca a que veio da tela. O substatus faz o mesmo par de chamadas do painel do ERP (troca + histórico),
# para o histórico de lá continuar certo. Criar ou apagar OS não existe na API web (só no sistema desktop).
class Outsider::Erp::Writer
  class Invalid < StandardError; end
  class Disabled < StandardError; end

  MAX_TEXT = 4000

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
    raise Invalid, 'value' unless @orders.substatus_options(order['Empresa']).include?(value)

    previous = order['SubStatus'].to_s
    return order if previous == value

    @client.update('UpdateSubStatusOS', order['CodigoOS'], { 'SubStatus' => value, 'listaEmpresas' => @settings.companies,
                                                             'Empresa' => order['Empresa'] })
    @client.update('GravaHistoricoSubStatusOS', order['CodigoOS'], {
                     'SubStatusAntigo' => previous.presence || value, 'SubStatusNovo' => value, 'listaEmpresas' => @settings.companies,
                     'idUsuario' => @settings.erp_user_id_for(@user), 'Empresa' => order['Empresa']
                   })
    changed(order, 'SubStatus', previous, value, conversation)
  end

  def field(company:, code:, field:, value:, conversation: nil)
    order = writable_order(company, code)
    endpoint = @settings.writable_fields[field.to_s]
    raise Invalid, 'field' unless endpoint

    value = value.to_s.strip
    raise Invalid, 'value' if value.length > MAX_TEXT

    previous = order[field.to_s].to_s
    return order if previous == value

    @client.update(endpoint, order['CodigoOS'], { field.to_s => value, 'listaEmpresas' => @settings.companies, 'Empresa' => order['Empresa'] })
    changed(order, field.to_s, previous, value, conversation)
  end

  private

  def writable_order(company, code)
    raise Disabled unless @settings.write_enabled?

    order = @orders.find(company.to_s, code)
    raise Invalid, 'order' unless order && @settings.companies.include?(order['Empresa'])

    order
  end

  def changed(order, field, previous, value, conversation)
    updated = order.merge(field => value)
    @orders.snapshot.patch { |item| updated if item['Empresa'] == order['Empresa'] && item['CodigoOS'] == order['CodigoOS'] }
    note(order, field, previous, value, conversation) if conversation && @settings.data['note_on_change']
    Rails.logger.info("[Outsider::Erp] conta #{@account.id} usuário #{@user.id} OS #{order['Empresa']}/#{order['CodigoOS']} #{field} alterado")
    updated
  end

  # nota privada na conversa: quem mudou o quê (fica no histórico do atendimento, não vai para o cliente)
  def note(order, field, previous, value, conversation)
    content = I18n.t('outsider_erp.note', os: order['CodigoOS'], company: order['Empresa'], field: field_label(field),
                                          from: previous.presence&.truncate(300) || '—', to: value.presence&.truncate(300) || '—',
                                          locale: :pt_BR)
    Messages::MessageBuilder.new(@user, conversation, { content: content, private: true }).perform
  end

  def field_label(field)
    I18n.t("outsider_erp.fields.#{field}", default: field, locale: :pt_BR)
  end
end
