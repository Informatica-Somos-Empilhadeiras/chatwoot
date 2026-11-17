# OUTSIDER: Baixar da área Teams pelo Chatwoot (endereços assinados, sem sessão, como Outsider::TeamsMediaController).
#   file: um arquivo, com o nome certo. O Chatwoot busca na Microsoft (com o token do dono da área) e repassa aos pedaços.
#   zip:  vários arquivos num .zip só (álbum, seleção de mensagens), também aos pedaços (Outsider::ZipStream); o que não
#         der para baixar fica listado em "nao-baixados.txt" dentro do zip.
# Antes, Baixar mandava o navegador direto para a Microsoft e, quando algo falhava, aparecia um 404 em branco ou
# "não foi possível baixar". Agora qualquer falha vira uma página curta dizendo o motivo, com o link para abrir o arquivo
# no Teams/SharePoint quando houver. Tudo é registrado no log com [outsider_teams_download].
class Outsider::TeamsDownloadsController < ActionController::API
  include ActionController::Live

  MAX_ZIP_ITEMS = 200

  REASONS = {
    'token' => 'Este link de download expirou. Volte ao Chatwoot, atualize a página (F5) e clique em Baixar de novo.',
    'not_found' => 'Não achei este arquivo no Chatwoot (a mensagem pode ter sido apagada).',
    'link' => 'O seu Teams está desconectado no Chatwoot. Entre de novo em Configurações > Meu Teams e tente outra vez.',
    'forbidden' => 'A Microsoft não deixou baixar este arquivo: quem enviou pode ter bloqueado o download ou tirado o seu acesso.',
    'gone' => 'O arquivo não existe mais no OneDrive/SharePoint (pode ter sido apagado ou movido).',
    'graph' => 'A Microsoft não respondeu agora. Tente de novo em alguns segundos.'
  }.freeze

  def file
    data = files_class.read_media(params[:t])
    return fail_with('token') unless data

    message = Outsider::TeamsMessage.includes(thread: :link).find_by(id: data['m'])
    attachment = message && Array(message.attachments)[data['i'].to_i]
    return fail_with('not_found', data) unless attachment
    return fail_with('link', data) unless message.thread.link&.status == 'active'

    service = files_class.new(message.thread.link)
    attachment = service.resolve!(message, data['i'].to_i) if attachment['hosted'].blank?
    send_stream(service, attachment, data)
  rescue Outsider::Teams::Graph::Client::Error => e
    fail_with(graph_reason(e), data, e, attachment)
  ensure
    response.stream.close
  end

  def zip
    data = files_class.read_zip(params[:t])
    return fail_with('token') unless data

    link = Outsider::TeamsLink.find_by(id: data['l'])
    return fail_with('link', data) unless link&.status == 'active'

    stream_zip(link, Array(data['items']).first(MAX_ZIP_ITEMS), data['n'])
  ensure
    response.stream.close
  end

  private

  def files_class
    Outsider::Teams::Graph::Files
  end

  def send_stream(service, attachment, data)
    first = true
    service.stream(attachment) do |chunk|
      if first
        start_file(attachment)
        first = false
      end
      response.stream.write(chunk)
    end
    start_file(attachment) if first # arquivo vazio
  rescue ActionController::Live::ClientDisconnected, IOError
    Rails.logger.info("[outsider_teams_download] cancelado message=#{data['m']}")
  end

  def start_file(attachment)
    name = attachment['name'].presence || 'arquivo'
    response.headers['Content-Type'] = attachment['mime'].presence || Marcel::MimeType.for(name: name) || 'application/octet-stream'
    response.headers['Content-Disposition'] = ActionDispatch::Http::ContentDisposition.format(disposition: 'attachment', filename: name)
    response.headers['Content-Length'] = attachment['size'].to_s if attachment['hosted'].blank? && attachment['size'].to_i.positive?
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['Last-Modified'] = Time.current.httpdate
  end

  def stream_zip(link, items, name)
    messages = Outsider::TeamsMessage.joins(:thread).where(outsider_teams_threads: { link_id: link.id })
                                     .where(id: items.map(&:first)).index_by(&:id)
    service = files_class.new(link)
    failed = []
    zip_headers(name)
    zip = Outsider::ZipStream.new(->(bytes) { response.stream.write(bytes) })
    items.each do |message_id, index|
      message = messages[message_id.to_i]
      attachment = message && Array(message.attachments)[index.to_i]
      next failed << "(mensagem #{message_id}) não encontrado" unless attachment
      next failed << "#{attachment['name']}: o zip chegou ao limite de 4 GB" if zip.full?
      # o Teams desconectou no meio: não adianta tentar o resto (cada tentativa pediria um token novo à Microsoft)
      next failed << "#{attachment['name']}: #{REASONS['link']}" if @link_lost

      add_to_zip(zip, service, message, index.to_i, attachment, failed)
    end
    zip.add('nao-baixados.txt') { |write| write.call("Arquivos que não entraram no zip:\r\n\r\n#{failed.join("\r\n")}\r\n") } if failed.any?
    zip.finish
  rescue ActionController::Live::ClientDisconnected, IOError
    Rails.logger.info("[outsider_teams_download] zip cancelado link=#{link.id}")
  end

  def add_to_zip(zip, service, message, index, attachment, failed)
    name = attachment['name'].presence || "arquivo-#{index + 1}"
    # o endereço (ou a imagem colada) vem antes de abrir a entrada: arquivo recusado não vira um arquivo vazio no zip
    if attachment['hosted'].present?
      bytes = service.hosted_bytes(attachment)[:body]
      return zip.add(name) { |write| write.call(bytes) }
    end

    url = service.content_location(service.resolve!(message, index))
    zip.add(name) { |write| files_class.stream(url) { |chunk| write.call(chunk) } }
  rescue Outsider::Teams::Graph::Client::Error, ArgumentError => e
    Rails.logger.warn("[outsider_teams_download] zip message=#{message.id} index=#{index}: #{e.message}")
    @link_lost = true if e.is_a?(Outsider::Teams::Graph::Client::Reconnect)
    failed << "#{attachment['name']}: #{REASONS[graph_reason(e)] || e.message}"
  end

  def zip_headers(name)
    filename = "#{name.to_s.tr('/\\:*?"<>|', '_').strip.presence || 'arquivos-teams'}.zip"
    response.headers['Content-Type'] = 'application/zip'
    response.headers['Content-Disposition'] = ActionDispatch::Http::ContentDisposition.format(disposition: 'attachment', filename: filename)
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['Last-Modified'] = Time.current.httpdate
  end

  def graph_reason(error)
    return 'forbidden' if error.status.to_i == 403
    return 'gone' if error.status.to_i == 404 || error.message == 'not_resolved'

    error.is_a?(Outsider::Teams::Graph::Client::Reconnect) ? 'link' : 'graph'
  end

  # página curta com o motivo (o download ainda não começou: dá para mudar a resposta)
  def fail_with(reason, data = nil, error = nil, attachment = nil)
    Rails.logger.warn("[outsider_teams_download] #{reason} message=#{data&.dig('m')} #{error&.message}".strip)
    return if response.committed?

    response.status = reason == 'graph' ? 502 : 404
    response.headers['Content-Type'] = 'text/html; charset=utf-8'
    response.headers['Cache-Control'] = 'no-store'
    response.stream.write(error_page(REASONS[reason], attachment))
  end

  def error_page(text, attachment)
    web = attachment && (attachment['web_url'].presence || attachment['url'])
    open = if web.to_s.start_with?('https://')
             %(<p><a href="#{ERB::Util.html_escape(web)}" target="_blank" rel="noopener">Abrir o arquivo no Teams/SharePoint</a></p>)
           end
    name = attachment && attachment['name'].present? ? "<p class=\"n\">#{ERB::Util.html_escape(attachment['name'])}</p>" : ''
    <<~HTML
      <!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
      <title>Não deu para baixar</title><style>
      body{font-family:system-ui,sans-serif;background:#f4f4f6;color:#1f2328;display:grid;place-items:center;min-height:100vh;margin:0}
      main{background:#fff;border-radius:16px;padding:28px 32px;max-width:440px;box-shadow:0 2px 12px rgb(0 0 0/.08)}
      h1{font-size:18px;margin:0 0 10px}p{margin:8px 0;line-height:1.5}.n{color:#5b616e;font-size:14px;word-break:break-all}
      a{color:#5b5fc7;font-weight:600}@media(prefers-color-scheme:dark){body{background:#111316;color:#e6e6e6}main{background:#1b1e23}.n{color:#9aa0aa}}
      </style></head><body><main><h1>Não deu para baixar o arquivo</h1>#{name}<p>#{ERB::Util.html_escape(text)}</p>#{open}</main></body></html>
    HTML
  end
end
