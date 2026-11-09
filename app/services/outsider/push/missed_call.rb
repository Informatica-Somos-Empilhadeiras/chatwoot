# OUTSIDER: aviso "Ligação perdida" (push), que chega mesmo com o Chatwoot fechado. Vai para o dono do negócio aberto
# de quem ligou; sem dono, para os vendedores do estado do número chamado; sem ninguém, para todos com ramal ligado.
# Botão "Ligar de volta" (liga pelo telefone do Chatwoot) e, clicando no aviso, abre Telefonia > Ligações.
class Outsider::Push::MissedCall
  def initialize(call)
    @call = call
    @account = call.account
    @settings = Outsider::Voice::Settings.new(@account)
  end

  def perform
    return 0 unless @call.inbound? && @call.missed?

    recipients.sum { |user| Outsider::Push::Sender.new(user).deliver(payload) }
  end

  def recipients
    agents = @settings.enabled_agents
    owner = @call.opportunity&.owner_id
    ids = if owner && agents.key?(owner) then [owner]
          else
            local = agents.select { |_id, agent| @call.state_code.present? && agent['state'] == @call.state_code }.keys
            local.presence || agents.keys
          end
    @account.users.where(id: ids).to_a.select do |user|
      Outsider::PushSetting.wants?(user, @account, 'calls_missed') && user.notification_subscriptions.browser_push.exists?
    end
  end

  private

  def caller
    @call.contact&.name.presence || pretty(@call.from_number).presence || 'Número desconhecido'
  end

  def body
    number = pretty(@call.from_number)
    parts = [@call.contact&.name.present? ? number : nil, "às #{@call.started_at.in_time_zone(time_zone).strftime('%H:%M')}"]
    parts << "para #{@call.to_number}" if @call.to_number.present? && @settings.data['numbers'].to_a.size > 1
    parts.compact.join(' · ')
  end

  # (62) 99999-8888; internacional e especiais como vieram
  def pretty(value)
    national = Outsider::Voice::PhoneNumber.national(value)
    return value.to_s unless national&.match?(Outsider::Voice::PhoneNumber::NATIONAL)

    "(#{national[0, 2]}) #{national[2..-5]}-#{national[-4..]}"
  end

  def time_zone
    @settings.data['time_zone'].presence || 'America/Sao_Paulo'
  end

  def payload
    Outsider::Push.payload(
      kind: 'phone', title: "Ligação perdida · #{caller}", body: body,
      url: "#{Outsider::Push.site}/app/accounts/#{@account.id}/telefonia/calls", tag: "call-#{@call.id}",
      person: @call.contact&.name.presence || caller, photo: @call.contact&.avatar_url.presence,
      open_label: 'Abrir Telefonia', call_label: 'Ligar de volta', number: @call.from_number
    )
  end
end
