# OUTSIDER: Configurações > Notificações (aviso novo no navegador e no celular).
#   Todos: o que me avisa (tudo ligado de início), meus aparelhos, ativar este aparelho e push de teste.
#   Administradores: a equipe, só se o push está ativo (nunca ativou ou bloqueou) e "Lembrar" a pessoa de ativar.
class Api::V1::Accounts::Outsider::PushController < Api::V1::Accounts::BaseController
  before_action :check_administrator, only: [:remind]

  def show
    render json: payload
  end

  def update
    prefs = params.fetch(:prefs, {}).permit(*::Outsider::PushSetting::DEFAULTS.keys).to_h
    setting.prefs = setting.merged_prefs.merge(prefs.transform_values { |value| ActiveModel::Type::Boolean.new.cast(value) })
    setting.save!
    render json: payload
  end

  # este navegador ativou o push: guarda o aparelho na tabela do Chatwoot e o nome dele aqui
  def register
    attributes = params.permit(:endpoint, :p256dh, :auth).to_h
    return render json: { error: 'invalid' }, status: :unprocessable_entity if attributes.values_at('endpoint', 'p256dh', 'auth').any?(&:blank?)

    NotificationSubscriptionBuilder.new(user: Current.user, params: { subscription_type: 'browser_push',
                                                                      subscription_attributes: attributes }).perform
    key = ::Outsider::PushSetting.device_key(attributes['endpoint'])
    devices = (setting.devices || {}).merge(key => { 'label' => params[:label].to_s.first(60).presence || 'Navegador',
                                                     'at' => Time.current.iso8601 })
    setting.update!(devices: devices, permission: 'granted')
    render json: payload
  end

  def unregister
    subscription = Current.user.notification_subscriptions.browser_push.find(params[:device_id])
    key = ::Outsider::PushSetting.device_key(subscription.subscription_attributes['endpoint'])
    subscription.destroy!
    setting.update!(devices: (setting.devices || {}).except(key)) if setting.persisted?
    render json: payload
  end

  # o navegador respondeu "Bloquear" (ou não tem push): aparece para o administrador
  def permission
    value = params[:permission].to_s
    setting.update!(permission: value) if ::Outsider::PushSetting::PERMISSIONS.include?(value)
    head :no_content
  end

  def test
    sent = ::Outsider::Push::Sender.new(Current.user).deliver(
      ::Outsider::Push.payload(kind: 'chatwoot', title: "#{Current.user.name} · Teste", body: 'Assim chegam os avisos do Chatwoot.',
                               url: "#{::Outsider::Push.site}/app/accounts/#{Current.account.id}/settings/outsider/notifications",
                               tag: "test-#{Time.current.to_i}", test: true)
    )
    render json: { sent: sent }
  end

  def remind
    person = Current.account.users.find(params[:user_id])
    ::Outsider::PushSetting.for(person, Current.account).update!(reminded_at: Time.current)
    head :no_content
  end

  private

  def setting
    @setting ||= ::Outsider::PushSetting.for(Current.user, Current.account)
  end

  def administrator?
    Current.account_user&.administrator?
  end

  def check_administrator
    render json: { error: 'forbidden' }, status: :forbidden unless administrator?
  end

  def payload
    {
      enabled: ::Outsider::Push.enabled?, vapid: VapidService.public_key.present?, prefs: setting.merged_prefs,
      permission: setting.permission, reminded_at: setting.reminded_at&.iso8601, devices: devices, admin: administrator?,
      team: administrator? ? team : []
    }
  end

  def devices
    labels = setting.devices || {}
    Current.user.notification_subscriptions.browser_push.order(:created_at).map do |subscription|
      endpoint = subscription.subscription_attributes['endpoint'].to_s
      info = labels[::Outsider::PushSetting.device_key(endpoint)] || {}
      { id: subscription.id, label: info['label'] || 'Navegador', activated_at: info['at'] || subscription.created_at.iso8601,
        tail: endpoint.last(24) }
    end
  end

  def team
    users = Current.account.users.order(:name).to_a
    counts = NotificationSubscription.browser_push.where(user_id: users.map(&:id)).group(:user_id).count
    settings = ::Outsider::PushSetting.where(account_id: Current.account.id, user_id: users.map(&:id)).index_by(&:user_id)
    users.map do |user|
      count = counts[user.id].to_i
      permission = settings[user.id]&.permission
      status = if count.positive?
                 'active'
               elsif permission == 'denied'
                 'blocked'
               else
                 'never'
               end
      { id: user.id, name: user.name, devices: count, status: status, reminded_at: settings[user.id]&.reminded_at&.iso8601 }
    end
  end
end
