# OUTSIDER: Gmail no bloco Google (Outsider::Apps::Google::Mail). Nada fica gravado no Chatwoot. Mesmos endereços e
# respostas do Outlook (MicrosoftMailController), para a tela ser uma só.
#   GET    folders            marcadores (Principal, Promoções..., Enviados, Lixeira e os da pessoa) com não lidas
#   GET    messages           lista (folder, filter, q, cursor), 25 por vez
#   GET    messages/:id       o e-mail inteiro (marca como lido) e quem é o remetente no Chatwoot (contato e conversa)
#   PATCH  messages/:id       lido/não lido, estrela
#   POST   messages/:id/move  mover (destination: marcador, TRASH/deleteditems, ALL/archive)
#   POST   messages           mandar (mode new/reply/reply_all/forward, to, cc, bcc, subject, text, files[])
class Api::V1::Accounts::Outsider::Apps::GoogleMailController < Api::V1::Accounts::Outsider::Apps::BaseController
  before_action { require_google(:mail) }

  def folders
    render json: { payload: mail.folders }
  rescue ::Outsider::Apps::Google::Client::Error => e
    graph_error(e)
  end

  def index
    render json: mail.messages(folder: params[:folder].presence || 'INBOX', filter: params[:filter], query: params[:q],
                               cursor: params[:cursor])
  rescue ::Outsider::Apps::Google::Client::Error => e
    graph_error(e)
  end

  def show
    message = mail.message(params[:id], mark_read: params[:mark_read] != 'false')
    render json: message.merge(chatwoot: ::Outsider::Apps::ContactMatch.for(Current.account, message.dig(:from, :email)))
  rescue ::Outsider::Apps::Google::Client::Error => e
    graph_error(e)
  end

  def create
    mode = %w[new reply reply_all forward].include?(params[:mode]) ? params[:mode] : 'new'
    to = emails(params[:to])
    return render_error_code('no_recipient', :unprocessable_entity) if to.empty? && %w[new forward].include?(mode)
    return render_error_code('no_source', :unprocessable_entity) if mode != 'new' && params[:source_id].blank?

    files = Array(params[:files]).select { |file| file.respond_to?(:original_filename) }
    return render_error_code('too_big', :unprocessable_entity) if files.sum(&:size) > ::Outsider::Apps::Google::Mail::MAX_SEND

    mail.deliver(mode: mode, html: params[:text].to_s, subject: params[:subject], to: to, cc: emails(params[:cc]),
                 bcc: emails(params[:bcc]), source_id: params[:source_id], files: files)
    head :created
  rescue ::Outsider::Apps::Google::Client::Error => e
    e.message == 'too_big' ? render_error_code('too_big', :unprocessable_entity) : graph_error(e)
  end

  def update
    read = params.key?(:read) ? cast(params[:read]) : nil
    flagged = params.key?(:flagged) ? cast(params[:flagged]) : nil
    render json: mail.update(params[:id], read: read, flagged: flagged)
  rescue ::Outsider::Apps::Google::Client::Error => e
    graph_error(e)
  end

  def move
    destination = params[:destination].to_s
    return render_error_code('invalid', :unprocessable_entity) if destination.blank?

    mail.move(params[:id], destination)
    head :no_content
  rescue ::Outsider::Apps::Google::Client::Error => e
    graph_error(e)
  end

  private

  def mail
    @mail ||= ::Outsider::Apps::Google::Mail.new(google_link)
  end
end
