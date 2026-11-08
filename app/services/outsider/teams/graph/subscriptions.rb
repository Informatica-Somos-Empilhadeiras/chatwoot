# OUTSIDER: os avisos de mensagem nova que a Microsoft manda ao Chatwoot (assinaturas do Microsoft Graph) para um
# colaborador do "Conectar meu Teams": uma para todos os chats dele (/users/{id}/chats/getAllMessages, só na versão beta
# em nome da pessoa) e uma por canal escolhido (/teams/{id}/channels/{id}/messages). Sem o conteúdo no aviso (não precisa
# de certificado): o Outsider::Teams::Graph::ReceiveJob busca a mensagem. Cada assinatura vale até 3 dias e o
# RenewJob renova; avisos acima de 1 hora exigem o endereço de ciclo de vida (lifecycle).
class Outsider::Teams::Graph::Subscriptions
  LIFETIME = 4200.minutes # a Microsoft aceita até 4320 (3 dias)
  RENEW_BEFORE = 30.hours
  NOTIFICATIONS_PATH = '/outsider/teams/graph/notifications'.freeze
  LIFECYCLE_PATH = '/outsider/teams/graph/lifecycle'.freeze

  def self.notification_url
    "#{Outsider::Teams::Graph::Login.site}#{NOTIFICATIONS_PATH}"
  end

  def self.public_https?
    uri = URI.parse(Outsider::Teams::Graph::Login.site)
    uri.is_a?(URI::HTTPS) && !uri.host.to_s.match?(/\A(localhost|127\.|0\.0\.0\.0|10\.|192\.168\.)/)
  rescue URI::InvalidURIError
    false
  end

  def initialize(link)
    @link = link
    @client = Outsider::Teams::Graph::Client.new(link)
  end

  # deixa as assinaturas iguais ao que a pessoa escolheu (chats ligados e canais marcados)
  def sync!
    wanted = desired
    @link.subscriptions.each do |subscription|
      key = key_of(subscription)
      next remove(subscription) unless wanted.key?(key)

      wanted.delete(key)
      create(subscription) if subscription.subscription_id.blank?
    end
    wanted.each_value { |attributes| create(@link.subscriptions.new(attributes)) }
    @link.subscriptions.reload
  end

  def remove_all!
    @link.subscriptions.each { |subscription| remove(subscription) }
  end

  def create(subscription)
    return fail!(subscription, 'public_url') unless self.class.public_https?

    subscription.save! if subscription.new_record?
    response = @client.post('/subscriptions', body(subscription), beta: subscription.kind == 'chats')
    subscription.update!(subscription_id: response['id'], expires_at: Time.zone.parse(response['expirationDateTime'].to_s),
                         last_error: nil)
  rescue Outsider::Teams::Graph::Client::Error => e
    fail!(subscription, e.message)
  end

  # renova; assinatura que a Microsoft já apagou é criada de novo
  def renew(subscription)
    return create(subscription) if subscription.subscription_id.blank?

    response = @client.patch("/subscriptions/#{subscription.subscription_id}", { expirationDateTime: expiration },
                             beta: subscription.kind == 'chats')
    subscription.update!(expires_at: Time.zone.parse(response['expirationDateTime'].to_s), last_error: nil)
  rescue Outsider::Teams::Graph::Client::Reconnect
    raise
  rescue Outsider::Teams::Graph::Client::Error => e
    raise unless e.status == 404

    subscription.update!(subscription_id: nil, expires_at: nil)
    create(subscription)
  end

  private

  def desired
    wanted = {}
    wanted['chats'] = { kind: 'chats', resource: "/users/#{@link.ms_user_id}/chats/getAllMessages" } if @link.sync_chats
    @link.channel_list.each do |channel|
      wanted["channel:#{channel['team_id']}:#{channel['channel_id']}"] = {
        kind: 'channel', team_id: channel['team_id'], channel_id: channel['channel_id'],
        resource: "/teams/#{channel['team_id']}/channels/#{channel['channel_id']}/messages"
      }
    end
    wanted
  end

  def key_of(subscription)
    subscription.kind == 'chats' ? 'chats' : "channel:#{subscription.team_id}:#{subscription.channel_id}"
  end

  def body(subscription)
    site = Outsider::Teams::Graph::Login.site
    { changeType: 'created,updated,deleted', notificationUrl: "#{site}#{NOTIFICATIONS_PATH}",
      lifecycleNotificationUrl: "#{site}#{LIFECYCLE_PATH}", resource: subscription.resource,
      expirationDateTime: expiration, clientState: subscription.client_state, includeResourceData: false }
  end

  def expiration
    (Time.current + LIFETIME).utc.iso8601
  end

  def remove(subscription)
    @client.delete("/subscriptions/#{subscription.subscription_id}", beta: subscription.kind == 'chats') if
      subscription.subscription_id.present?
  rescue Outsider::Teams::Graph::Client::Error => e
    Rails.logger.info("[outsider_teams_graph] subscription delete: #{e.message}")
  ensure
    subscription.destroy! if subscription.persisted?
  end

  def fail!(subscription, reason)
    subscription.save! if subscription.new_record?
    subscription.update!(last_error: reason.to_s.first(250))
    false
  end
end
