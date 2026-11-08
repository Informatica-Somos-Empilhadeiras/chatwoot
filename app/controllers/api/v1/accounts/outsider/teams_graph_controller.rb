# OUTSIDER: Configurações > Microsoft Teams, parte do "Conectar meu Teams" (login com a conta Microsoft de cada pessoa).
#   Todos: ver a própria ligação, entrar com a conta Microsoft (authorize + finish), escolher chats e canais, desconectar.
#   Administradores: o aplicativo da empresa no Microsoft Entra ID (cadastro único do TI), o consentimento pela empresa
#   e a lista de quem está conectado (só a situação; o conteúdo das conversas fica com cada pessoa).
class Api::V1::Accounts::Outsider::TeamsGraphController < Api::V1::Accounts::BaseController
  before_action :check_administrator, only: [:save_app, :consent, :destroy_link]
  before_action :require_app, only: [:authorize, :consent, :finish]
  before_action :require_link, only: [:directory, :update_me]

  rescue_from ActiveRecord::RecordInvalid do |error|
    render json: { error: 'invalid', message: error.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  def show
    render json: {
      admin: administrator?, configured: graph_app.present? && graph_app.client_secret.present?,
      consent_granted_at: graph_app&.consent_granted_at&.iso8601, redirect_uri: oauth.redirect_uri,
      notification_url: ::Outsider::Teams::Graph::Subscriptions.notification_url,
      public_https: ::Outsider::Teams::Graph::Subscriptions.public_https?, permissions: oauth::PERMISSIONS,
      app: administrator? && graph_app ? { client_id: graph_app.client_id, tenant_id: graph_app.tenant_id } : nil,
      me: ::Outsider::Teams::Graph::Json.link(my_link),
      links: administrator? ? links.includes(:user, :subscriptions).order(:created_at).map { |link| links_row(link) } : []
    }
  end

  def save_app
    app = graph_app || ::Outsider::TeamsGraphApp.new(account: Current.account)
    attributes = params.permit(:client_id, :tenant_id).to_h.transform_values { |value| value.to_s.strip.downcase }
    changed = attributes['client_id'] != app.client_id || attributes['tenant_id'] != app.tenant_id
    app.assign_attributes(attributes.merge(updated_by_id: Current.user.id))
    app.client_secret = params[:client_secret].to_s.strip if params[:client_secret].present?
    app.consent_granted_at = nil if changed
    app.save!
    head :no_content
  end

  def consent
    render json: { url: oauth.new(graph_app).admin_consent_url(Current.user) }
  end

  def authorize
    render json: { url: oauth.new(graph_app).authorize_url(Current.user) }
  end

  # volta do login (ou do consentimento) da Microsoft, com a sessão da pessoa
  def finish
    state = oauth.read_state(params[:state])
    return render_error('state', :unprocessable_entity) unless state && state['a'] == Current.account.id && state['u'] == Current.user.id
    return render_error(params[:error_description].presence || params[:error], :unprocessable_entity) if params[:error].present?

    if state['k'] == 'consent'
      return render_error('forbidden', :forbidden) unless administrator?

      graph_app.update!(consent_granted_at: Time.current) if params[:admin_consent].to_s.casecmp('true').zero?
      return head :no_content
    end

    link = ::Outsider::Teams::Graph::Connect.new(graph_app, Current.user).perform(params[:code])
    render json: ::Outsider::Teams::Graph::Json.link(link)
  rescue ::Outsider::Teams::Graph::Connect::Error => e
    render_error(e.message, :unprocessable_entity)
  end

  def directory
    render json: { payload: ::Outsider::Teams::Graph::Directory.new(my_link).teams(refresh: params[:refresh].present?) }
  rescue ::Outsider::Teams::Graph::Client::Error => e
    render_error(e.message, :bad_gateway)
  end

  # chats ligados ou não, os canais escolhidos (só canais das equipes da própria pessoa) e o jeito de ver os canais
  # (channel_view: 'conversa' = mensagens em sequência, como no WhatsApp; 'publicacoes' = cartões, como no Teams)
  def update_me
    my_link.channel_view = params[:channel_view] if params[:channel_view].in?(%w[conversa publicacoes])
    if params.key?(:channels) || params.key?(:sync_chats)
      my_link.assign_attributes(sync_chats: ActiveModel::Type::Boolean.new.cast(params.fetch(:sync_chats, my_link.sync_chats)),
                                channels: chosen_channels)
      my_link.save!
      ::Outsider::Teams::Graph::Subscriptions.new(my_link).sync!
    else
      my_link.save!
    end
    render json: ::Outsider::Teams::Graph::Json.link(my_link.reload)
  rescue ::Outsider::Teams::Graph::Client::Error => e
    render_error(e.message, :bad_gateway)
  end

  def disconnect
    disconnect!(my_link) if my_link
    head :no_content
  end

  def destroy_link
    disconnect!(links.find(params[:link_id]))
    head :no_content
  end

  private

  def oauth
    ::Outsider::Teams::Graph::Login
  end

  def administrator?
    Current.account_user&.administrator?
  end

  def check_administrator
    render_error('forbidden', :forbidden) unless administrator?
  end

  def graph_app
    @graph_app ||= ::Outsider::TeamsGraphApp.find_by(account_id: Current.account.id)
  end

  def links
    ::Outsider::TeamsLink.where(account_id: Current.account.id)
  end

  def my_link
    @my_link ||= links.find_by(user_id: Current.user.id)
  end

  def require_app
    render_error('not_configured', :unprocessable_entity) unless graph_app && graph_app.client_secret.present?
  end

  def require_link
    render_error('not_connected', :unprocessable_entity) unless my_link && my_link.status != 'disconnected'
  end

  def chosen_channels
    wanted = Array(params[:channels]).map { |channel| channel.permit(:team_id, :channel_id).to_h }
    available = ::Outsider::Teams::Graph::Directory.new(my_link).teams.flat_map do |team|
      team['channels'].map { |channel| channel.merge('team_id' => team['team_id'], 'team_name' => team['team_name']) }
    end
    wanted.filter_map do |item|
      found = available.find { |channel| channel['team_id'] == item['team_id'] && channel['channel_id'] == item['channel_id'] }
      found&.slice('team_id', 'team_name', 'channel_id', 'channel_name')
    end.uniq.first(50)
  end

  def links_row(link)
    { id: link.id, user_id: link.user_id, user_name: link.user&.name, display_name: link.display_name, email: link.email,
      status: link.status, sync_chats: link.sync_chats, channels_count: link.channel_list.size,
      last_activity_at: link.last_activity_at&.iso8601, problem: link.subscriptions.any? { |subscription| subscription.last_error.present? } }
  end

  def disconnect!(link)
    ::Outsider::Teams::Graph::Subscriptions.new(link).remove_all! if link.status == 'active'
    link.update!(status: 'disconnected', access_token_encrypted: nil, refresh_token_encrypted: nil, token_expires_at: nil)
    link.subscriptions.delete_all
    ::Outsider::Teams::Graph::Notifier.changed(link)
  rescue ::Outsider::Teams::Graph::Client::Error
    link.update!(status: 'disconnected', access_token_encrypted: nil, refresh_token_encrypted: nil, token_expires_at: nil)
    link.subscriptions.delete_all
  end

  def render_error(message, status)
    render json: { error: message.to_s.split(':').first, message: message.to_s }, status: status
  end
end
