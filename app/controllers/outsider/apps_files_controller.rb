# OUTSIDER: abre ou baixa um anexo de e-mail dos aplicativos pelo endereço assinado (Outsider::Apps::FileToken), sem sessão,
# para servir em <img> e em Baixar. O Chatwoot lê da Microsoft com o token do dono e repassa aos pedaços; nada fica gravado.
# Imagem abre na tela (inline); o resto vem como download. Falha vira uma página curta dizendo o motivo.
class Outsider::AppsFilesController < ActionController::API
  include ActionController::Live

  INLINE = %w[image/png image/jpeg image/gif image/webp image/bmp application/pdf].freeze
  REASONS = {
    'token' => 'Este link expirou. Volte ao Chatwoot, abra o e-mail de novo e clique no anexo.',
    'link' => 'A sua conta está desconectada no Chatwoot. Entre de novo em Configurações > Meu Teams e tente outra vez.',
    'graph' => 'A Microsoft não entregou este anexo agora. Tente de novo em alguns segundos.'
  }.freeze

  def show
    data = Outsider::Apps::FileToken.read(params[:t])
    return fail_with('token') unless data && data['k'] == 'ms_attachment'

    link = Outsider::TeamsLink.find_by(id: data['l'])
    return fail_with('link') unless Outsider::Teams::Graph::Login.allows?(link, :mail)

    mail = Outsider::Apps::Microsoft::Mail.new(link)
    info = mail.attachment_info(data['message_id'], data['attachment_id'])
    start_file(info)
    mail.stream_attachment(data['message_id'], data['attachment_id']) { |chunk| response.stream.write(chunk) }
  rescue Outsider::Teams::Graph::Client::Error => e
    Rails.logger.warn("[outsider_apps_file] #{e.message}")
    fail_with(e.is_a?(Outsider::Teams::Graph::Client::Reconnect) ? 'link' : 'graph') unless response.committed?
  rescue ActionController::Live::ClientDisconnected, IOError
    nil
  ensure
    response.stream.close
  end

  private

  def start_file(info)
    name = info[:name]
    type = info[:content_type].presence || Marcel::MimeType.for(name: name) || 'application/octet-stream'
    disposition = INLINE.include?(type) && params[:download].blank? ? 'inline' : 'attachment'
    response.headers['Content-Type'] = type
    response.headers['Content-Disposition'] = ActionDispatch::Http::ContentDisposition.format(disposition: disposition, filename: name)
    response.headers['Cache-Control'] = 'private, max-age=3600'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    # o leitor de PDF do navegador não abre com sandbox; imagem e download ficam isolados
    response.headers['Content-Security-Policy'] = "default-src 'none'; img-src 'self' data:; sandbox" unless type == 'application/pdf'
  end

  def fail_with(reason)
    response.status = reason == 'token' ? 410 : 502
    response.headers['Content-Type'] = 'text/html; charset=utf-8'
    response.stream.write(<<~HTML)
      <!doctype html><html lang="pt-BR"><meta charset="utf-8"><title>Anexo</title>
      <body style="font-family:system-ui,sans-serif;max-width:520px;margin:15vh auto;padding:0 16px;color:#1f2328">
      <h2>Não deu para abrir o anexo</h2><p>#{ERB::Util.html_escape(REASONS[reason])}</p></body></html>
    HTML
  end
end
