# OUTSIDER: abre ou baixa um arquivo dos aplicativos pelo endereço assinado (Outsider::Apps::FileToken), sem sessão, para
# servir em <img>, no visualizador e em Baixar: anexo de e-mail do Outlook ou do Gmail, arquivo, exportação (Documentos do
# Google em PDF/Word/Excel/PowerPoint) e miniatura do Google Drive. O Chatwoot lê da Microsoft/Google com o token do dono
# e repassa aos pedaços; nada fica gravado. Imagem e PDF abrem na tela (inline); o resto vem como download. Falha vira uma
# página curta dizendo o motivo.
class Outsider::AppsFilesController < ActionController::API
  include ActionController::Live

  INLINE = %w[image/png image/jpeg image/gif image/webp image/bmp application/pdf video/mp4 video/webm video/quicktime text/plain
              text/csv].freeze
  GOOGLE = %w[g_attachment g_file g_export g_thumb].freeze
  SLICE = 1.megabyte
  REASONS = {
    'token' => 'Este link expirou. Volte ao Chatwoot e abra o arquivo de novo.',
    'link' => 'A sua conta está desconectada no Chatwoot. Entre de novo em Configurações > Microsoft Teams e tente outra vez.',
    'glink' => 'A sua conta Google está desconectada no Chatwoot. Entre de novo em Configurações > Google e tente outra vez.',
    'graph' => 'A Microsoft não entregou este arquivo agora. Tente de novo em alguns segundos.',
    'google' => 'O Google não entregou este arquivo agora. Tente de novo em alguns segundos.'
  }.freeze

  def show
    data = Outsider::Apps::FileToken.read(params[:t])
    return fail_with('token') unless data
    return google(data) if GOOGLE.include?(data['k'])
    return fail_with('token') unless data['k'] == 'ms_attachment'

    microsoft(data)
  rescue ActionController::Live::ClientDisconnected, IOError
    nil
  ensure
    response.stream.close
  end

  private

  def microsoft(data)
    link = Outsider::TeamsLink.find_by(id: data['l'])
    return fail_with('link') unless Outsider::Teams::Graph::Login.allows?(link, :mail)

    mail = Outsider::Apps::Microsoft::Mail.new(link)
    info = mail.attachment_info(data['message_id'], data['attachment_id'])
    start_file(info)
    mail.stream_attachment(data['message_id'], data['attachment_id']) { |chunk| response.stream.write(chunk) }
  rescue Outsider::Teams::Graph::Client::Error => e
    Rails.logger.warn("[outsider_apps_file] #{e.message}")
    fail_with(e.is_a?(Outsider::Teams::Graph::Client::Reconnect) ? 'link' : 'graph') unless response.committed?
  end

  def google(data)
    link = Outsider::GoogleLink.find_by(id: data['l'])
    return fail_with('glink') unless link&.allows?(data['k'] == 'g_attachment' ? :mail : :drive)

    case data['k']
    when 'g_attachment'
      file = Outsider::Apps::Google::Mail.new(link).attachment(data['message_id'], data['part_id'])
      write_all(file)
    when 'g_thumb'
      image = Outsider::Apps::Google::Drive.new(link).thumbnail(data['file_id'])
      write_all(image.merge(name: 'miniatura.jpg'))
    else
      drive = Outsider::Apps::Google::Drive.new(link)
      source = drive.source(data)
      start_file(source)
      drive.stream(source) { |chunk| response.stream.write(chunk) }
    end
  rescue Outsider::Apps::Google::Client::Error => e
    Rails.logger.warn("[outsider_apps_file] google #{e.message}")
    fail_with(e.is_a?(Outsider::Apps::Google::Client::Reconnect) ? 'glink' : 'google') unless response.committed?
  end

  # o Gmail entrega o anexo inteiro: vai para o navegador em pedaços de 1 MB
  def write_all(file)
    body = file[:body].to_s
    start_file(file.merge(size: body.bytesize))
    (0...body.bytesize).step(SLICE) { |offset| response.stream.write(body.byteslice(offset, SLICE)) }
  end

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
      <!doctype html><html lang="pt-BR"><meta charset="utf-8"><title>Arquivo</title>
      <body style="font-family:system-ui,sans-serif;max-width:520px;margin:15vh auto;padding:0 16px;color:#1f2328">
      <h2>Não deu para abrir o arquivo</h2><p>#{ERB::Util.html_escape(REASONS[reason])}</p></body></html>
    HTML
  end
end
