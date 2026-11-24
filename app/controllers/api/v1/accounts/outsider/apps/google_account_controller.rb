# OUTSIDER: Configurações > Google (bloco Google dos Aplicativos).
#   Todos: a própria conta Google (entrar com authorize + finish, entrar de novo, desconectar).
#   Administradores: o aplicativo da empresa no Google Cloud (ID do cliente e chave secreta, cadastro único do TI) e a
#   lista de quem está conectado (só a situação; e-mails, eventos e arquivos ficam com cada pessoa).
class Api::V1::Accounts::Outsider::Apps::GoogleAccountController < Api::V1::Accounts::Outsider::Apps::BaseController
  before_action :check_administrator, only: [:save_app, :destroy_link]
  before_action :require_app, only: [:authorize, :finish]

  rescue_from ActiveRecord::RecordInvalid do |error|
    render json: { error: 'invalid', message: error.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  def show
    render json: {
      admin: administrator?, configured: google_app.present?, redirect_uri: login_class.redirect_uri, origin: login_class.site,
      public_https: login_class.site.start_with?('https://'),
      app: administrator? && google_app ? { client_id: google_app.client_id } : nil,
      me: link_json(google_link),
      links: administrator? ? links.includes(:user).order(:created_at).map { |link| link_json(link).merge(user: link.user&.name) } : []
    }
  end

  def save_app
    app = google_app || ::Outsider::GoogleApp.new(account_id: Current.account.id)
    app.client_id = params[:client_id].to_s.strip
    app.client_secret = params[:client_secret].to_s.strip if params[:client_secret].present?
    app.updated_by_id = Current.user.id
    app.save!
    head :no_content
  end

  def authorize
    render json: { url: login.authorize_url(Current.user) }
  end

  # volta da tela do Google, com a sessão da pessoa: troca o código pelos tokens e guarda a ligação
  def finish
    state = login_class.read_state(params[:state])
    return render_error_code('state', :unprocessable_entity) unless state && state['a'] == Current.account.id && state['u'] == Current.user.id
    return render json: { error: 'denied', message: params[:error].to_s.first(200) }, status: :unprocessable_entity if params[:error].present?

    link = connect!(login.exchange(params[:code]))
    render json: link_json(link)
  rescue ::Outsider::Apps::Google::Login::Error => e
    code = %w[already_linked no_refresh_token].include?(e.message) ? e.message : 'google'
    render json: { error: code, message: e.message.to_s.first(300) }, status: :unprocessable_entity
  end

  # tira o acesso também na conta Google (se falhar, a pessoa tira em myaccount.google.com) e apaga a ligação
  def disconnect
    disconnect!(google_link) if google_link
    head :no_content
  end

  def destroy_link
    disconnect!(links.find(params[:link_id]))
    head :no_content
  end

  private

  def login_class
    ::Outsider::Apps::Google::Login
  end

  def login
    login_class.new(google_app)
  end

  def google_app
    @google_app ||= ::Outsider::GoogleApp.find_by(account_id: Current.account.id)
  end

  def links
    ::Outsider::GoogleLink.where(account_id: Current.account.id)
  end

  def administrator?
    Current.account_user&.administrator?
  end

  def check_administrator
    render_error_code('forbidden', :forbidden) unless administrator?
  end

  def require_app
    render_error_code('not_configured', :unprocessable_entity) if google_app&.client_secret.blank?
  end

  def connect!(tokens)
    profile = login.profile(tokens[:access_token])
    other = links.find_by(google_user_id: profile[:sub])
    raise ::Outsider::Apps::Google::Login::Error, 'already_linked' if other && other.user_id != Current.user.id

    link = links.find_or_initialize_by(user_id: Current.user.id)
    link.assign_attributes(google_user_id: profile[:sub], email: profile[:email], display_name: profile[:name].presence || Current.user.name,
                           access_token: tokens[:access_token], refresh_token: tokens[:refresh_token], token_expires_at: tokens[:expires_at],
                           scopes: tokens[:scopes], status: 'active', last_error: nil, history_id: nil, checked_at: nil)
    raise ::Outsider::Apps::Google::Login::Error, 'no_refresh_token' if link.refresh_token.blank?

    link.save!
    start_watch(link)
    ::Outsider::Apps::Notifier.broadcast(Current.user, Current.account.id, provider: 'google', app: 'mail', action: 'changed')
    link
  end

  # o observador do Gmail começa de agora (o que já está na caixa não vira aviso)
  def start_watch(link)
    ::Outsider::Apps::Google::Watcher.new(link).start! if link.allows?(:mail)
  rescue ::Outsider::Apps::Google::Client::Error => e
    Rails.logger.info("[outsider_google] start watch: #{e.message}")
  end

  def disconnect!(link)
    login_class.revoke(link.refresh_token.presence || link.access_token)
    Rails.cache.delete(::Outsider::Apps::Google::Mail.unread_key(link))
    ::Outsider::Apps::Notifier.broadcast(link.user, link.account_id, provider: 'google', app: 'mail', action: 'changed')
    link.destroy!
  end

  def link_json(link)
    return nil if link.nil?

    { id: link.id, email: link.email, name: link.display_name, status: link.status, mail: link.allows?(:mail),
      calendar: link.allows?(:calendar), drive: link.allows?(:drive), connected_at: link.created_at&.iso8601,
      checked_at: link.checked_at&.iso8601, last_error: link.status == 'reconnect' ? link.last_error : nil }
  end
end
