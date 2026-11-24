# OUTSIDER: base das telas dos aplicativos (blocos Microsoft e Google do menu). Cada pessoa só vê a própria conta: as
# chamadas usam sempre a ligação de quem está logado, nunca a de outro colaborador. Os erros da Microsoft/Google viram
# { error, message } com um código que a tela traduz.
class Api::V1::Accounts::Outsider::Apps::BaseController < Api::V1::Accounts::BaseController
  private

  def microsoft_link
    @microsoft_link ||= ::Outsider::TeamsLink.find_by(account_id: Current.account.id, user_id: Current.user.id)
  end

  # feature: :mail (Outlook, versão 4) ou nil (OneDrive, desde a versão 1)
  def require_microsoft(feature = nil)
    return render_error_code('not_connected', :unprocessable_entity) unless microsoft_link&.status == 'active'
    return if feature.nil? || ::Outsider::Teams::Graph::Login.allows?(microsoft_link, feature)

    render_error_code('scope_outdated', :unprocessable_entity)
  end

  def google_link
    @google_link ||= ::Outsider::GoogleLink.find_by(account_id: Current.account.id, user_id: Current.user.id)
  end

  # feature: :mail (Gmail), :calendar (Agenda) ou :drive (Drive); a pessoa pode ter desmarcado uma delas na tela do Google
  def require_google(feature)
    return render_error_code('not_connected', :unprocessable_entity) if google_link.nil? || google_link.status == 'disconnected'
    return render_error_code('reconnect', :unprocessable_entity) if google_link.status == 'reconnect'

    render_error_code('scope_outdated', :unprocessable_entity) unless google_link.allows?(feature)
  end

  # os erros do Google usam as mesmas classes dos da Microsoft (Outsider::Apps::Google::Client)
  def graph_error(error)
    return render_error_code('reconnect', :unprocessable_entity) if error.is_a?(::Outsider::Teams::Graph::Client::Reconnect)

    code = { 404 => 'not_found', 403 => 'forbidden', 429 => 'busy', 422 => 'invalid' }[error.status] || 'graph'
    render json: { error: code, message: error.message.to_s.first(300) }, status: error.status == 404 ? :not_found : :bad_gateway
  end

  def render_error_code(code, status)
    render json: { error: code, message: code }, status: status
  end

  def cast(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end

  def emails(value)
    list = value.is_a?(String) ? value.split(/[,;\s]+/) : Array(value)
    list.map(&:to_s).map(&:strip).grep(URI::MailTo::EMAIL_REGEXP).uniq
  end
end
