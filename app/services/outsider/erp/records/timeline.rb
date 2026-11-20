# OUTSIDER: a linha do tempo do painel de detalhe da seção ERP (como a jornada do CRM): o que aconteceu com o
# orçamento, as OS e os pedidos da corrente (datas do próprio ERP) e o que foi feito pelo chat (criação, liberação de
# desconto, edições do orçamento gravado, envios por WhatsApp/e-mail). A tela só traduz o "type".
class Outsider::Erp::Records::Timeline
  def initialize(account)
    @account = account
  end

  def build(detail)
    events = chain_events(detail['chain']) + header_events(detail) + chat_events(detail['budget_record'])
    events.select { |event| event['at'].present? }.sort_by { |event| time(event['at']) || Time.zone.at(0) }
  end

  private

  def chain_events(chain)
    Array(chain).flat_map do |node|
      list = [event(node['data'], 'created', node)]
      list << event(node['entrega'], 'delivered', node) if node['kind'] == 'orders' && node['entrega'].present?
      list << event(node['data'], 'invoiced', node).merge('nota' => node['nota']) if node['kind'] == 'sales' && node['nota']
      list
    end
  end

  def header_events(detail)
    header = detail['header'] || {}
    return [] unless detail['kind'] == 'quotes'

    list = []
    list << event(header['data_status'], 'status', detail).merge('status' => header['status']) if header['status'] != 'NEGOCIAÇÃO'
    authorized = header['autorizado_por'].to_i.positive?
    list << event(header['data_autorizado'], 'authorized', detail).merge('name' => header['autorizado_por_nome']) if authorized
    list
  end

  def chat_events(budget)
    return [] unless budget

    list = [{ 'at' => budget.created_at.iso8601, 'type' => 'chat_created', 'name' => budget.user&.name }]
    approval = budget.approval.to_h
    list << { 'at' => approval['at'], 'type' => 'chat_approved', 'name' => approval['by_name'] } if approval['by_code'].present?
    list += Array(budget.erp_result.to_h['edits']).map { |edit| { 'at' => edit['at'], 'type' => 'chat_edited', 'name' => edit['name'] } }
    list + budget.sends.includes(:user).order(:created_at).map { |send| send_event(send) }
  end

  def send_event(send)
    { 'at' => send.created_at.iso8601, 'type' => 'sent', 'channel' => send.channel, 'status' => send.status, 'name' => send.user&.name,
      'to' => Array(send.recipients).first(3).map { |item| recipient(item) } }
  end

  def recipient(item) = item.is_a?(Hash) ? item['name'] || item['email'] || item['phone'] : item

  def event(at, type, source)
    { 'at' => at, 'type' => type, 'kind' => source['kind'], 'numero' => source['numero'] }
  end

  def time(value)
    value.is_a?(String) ? Time.zone.parse(value) : value
  rescue ArgumentError
    nil
  end
end
