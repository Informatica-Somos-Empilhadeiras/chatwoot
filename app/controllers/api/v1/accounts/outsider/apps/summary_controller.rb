# OUTSIDER: o que o menu precisa dos aplicativos: quem está conectado e as não lidas do Outlook (1 minuto no cache).
# Falha da Microsoft só deixa o número sem aparecer; o menu continua.
class Api::V1::Accounts::Outsider::Apps::SummaryController < Api::V1::Accounts::Outsider::Apps::BaseController
  def show
    render json: { microsoft: microsoft_summary }
  end

  private

  def microsoft_summary
    link = microsoft_link
    # configured: a empresa já ligou o app da Microsoft (Configurações > Microsoft Teams); o bloco aparece para todos
    configured = ::Outsider::TeamsGraphApp.exists?(account_id: Current.account.id)
    return { configured: configured, connected: false } if link.nil? || link.status == 'disconnected'

    mail = ::Outsider::Teams::Graph::Login.allows?(link, :mail)
    calendar = ::Outsider::Teams::Graph::Login.allows?(link, :calendar)
    { configured: configured, connected: true, status: link.status, email: link.email, mail: mail, calendar: calendar,
      unread_mail: mail ? unread(link) : 0 }
  end

  def unread(link)
    ::Outsider::Apps::Microsoft::Mail.new(link).unread_count
  rescue ::Outsider::Teams::Graph::Client::Error
    0
  end
end
