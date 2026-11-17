# OUTSIDER: miniaturas, imagens e downloads dos arquivos da área Teams, por endereço assinado (Outsider::Teams::Graph::
# Files.media_url, vale 2 horas e só sai para o dono da área). Nada fica gravado no Chatwoot:
#   thumb/image de arquivo do OneDrive/SharePoint: redireciona para a miniatura temporária da Microsoft;
#   image/download de imagem colada no Teams: lê do Graph com o token do dono e repassa;
#   download de arquivo (e audio, para tocar no Chatwoot): redireciona para o endereço temporário de download da Microsoft.
class Outsider::TeamsMediaController < ActionController::API
  def show
    data = Outsider::Teams::Graph::Files.read_media(params[:t])
    # Baixar de antes desta versão (endereço antigo ainda na tela): vai para o download pelo Chatwoot
    return redirect_to("#{Outsider::Teams::Graph::Files::DOWNLOAD_PATH}?t=#{CGI.escape(params[:t].to_s)}") if data&.dig('k') == 'download'

    message = data && Outsider::TeamsMessage.includes(thread: :link).find_by(id: data['m'])
    @attachment = message && Array(message.attachments)[data['i'].to_i]
    @link = message&.thread&.link
    return missing(data ? 'not_found' : 'token') unless @attachment
    return missing("link_#{@link&.status}") unless @link&.status == 'active'

    @files = Outsider::Teams::Graph::Files.new(@link)
    @attachment = @files.resolve!(message, data['i'].to_i) if @attachment['hosted'].blank?
    respond_with(data['k'])
  rescue Outsider::Teams::Graph::Client::Error => e
    Rails.logger.warn("[outsider_teams_media] #{data&.dig('k')} message=#{data&.dig('m')} graph: #{e.message}")
    head(e.status.to_i.in?([403, 404]) ? :not_found : :bad_gateway)
  end

  private

  def missing(reason)
    Rails.logger.info("[outsider_teams_media] 404 #{reason}")
    head :not_found
  end

  def respond_with(kind)
    return send_hosted(kind == 'download' ? 'attachment' : 'inline') if @attachment['hosted'].present?
    # bytes=1: o áudio passa pelo Chatwoot (para a transcrição no navegador ler o arquivo sem bloqueio de origem)
    return pass_through(@files.content_location(@attachment)) if kind == 'audio' && params[:bytes].present?
    # áudio, vídeo e imagem inteira (visualizador): direto do endereço temporário da Microsoft (aceita pular no vídeo)
    return go(@files.content_location(@attachment)) if %w[audio video full].include?(kind)

    go(@files.thumbnail_url(@attachment, kind == 'image' ? 'large' : 'medium'))
  end

  def send_hosted(disposition)
    image = @files.hosted_bytes(@attachment)
    response.headers['Cache-Control'] = 'private, max-age=3600'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    type = image[:content_type].start_with?('image/') ? image[:content_type] : 'application/octet-stream'
    send_data image[:body], type: type, disposition: disposition, filename: @attachment['name'].presence || 'imagem.png'
  end

  PASS_THROUGH_MAX = 40.megabytes

  def pass_through(url)
    return head(:not_found) unless Outsider::Teams::Graph::Files.microsoft_url?(url)

    file = HTTParty.get(url, timeout: 60)
    return head(:bad_gateway) unless file.success?
    return head(:payload_too_large) if file.body.to_s.bytesize > PASS_THROUGH_MAX

    response.headers['Cache-Control'] = 'private, max-age=600'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    type = file.headers['content-type'].to_s.split(';').first.presence || 'application/octet-stream'
    send_data file.body, type: type.start_with?('audio/', 'video/') ? type : 'application/octet-stream', disposition: 'inline',
                         filename: @attachment['name'].presence || 'audio'
  rescue HTTParty::Error, SocketError, Net::OpenTimeout, Net::ReadTimeout
    head :bad_gateway
  end

  def go(url)
    return head(:not_found) unless Outsider::Teams::Graph::Files.microsoft_url?(url)

    response.headers['Cache-Control'] = 'private, max-age=600'
    redirect_to url, allow_other_host: true
  end
end
