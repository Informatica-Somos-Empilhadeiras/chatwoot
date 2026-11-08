# OUTSIDER: miniaturas, imagens e downloads dos arquivos da área Teams, por endereço assinado (Outsider::Teams::Graph::
# Files.media_url, vale 2 horas e só sai para o dono da área). Nada fica gravado no Chatwoot:
#   thumb/image de arquivo do OneDrive/SharePoint: redireciona para a miniatura temporária da Microsoft;
#   image/download de imagem colada no Teams: lê do Graph com o token do dono e repassa;
#   download de arquivo: redireciona para o endereço temporário de download da Microsoft.
class Outsider::TeamsMediaController < ActionController::API
  def show
    data = Outsider::Teams::Graph::Files.read_media(params[:t])
    message = data && Outsider::TeamsMessage.includes(thread: :link).find_by(id: data['m'])
    @attachment = message && Array(message.attachments)[data['i'].to_i]
    @link = message&.thread&.link
    return head(:not_found) unless @attachment && @link&.status == 'active'

    @files = Outsider::Teams::Graph::Files.new(@link)
    @attachment = @files.resolve!(message, data['i'].to_i) if @attachment['hosted'].blank?
    respond_with(data['k'])
  rescue Outsider::Teams::Graph::Client::Error
    head :bad_gateway
  end

  private

  def respond_with(kind)
    return send_hosted(kind == 'download' ? 'attachment' : 'inline') if @attachment['hosted'].present?
    return go(@files.download_url(@attachment)) if kind == 'download'

    go(@files.thumbnail_url(@attachment, kind == 'image' ? 'large' : 'medium'))
  end

  def send_hosted(disposition)
    image = @files.hosted_bytes(@attachment)
    response.headers['Cache-Control'] = 'private, max-age=3600'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    type = image[:content_type].start_with?('image/') ? image[:content_type] : 'application/octet-stream'
    send_data image[:body], type: type, disposition: disposition, filename: @attachment['name'].presence || 'imagem.png'
  end

  def go(url)
    return head(:not_found) unless Outsider::Teams::Graph::Files.microsoft_url?(url)

    response.headers['Cache-Control'] = 'private, max-age=600'
    redirect_to url, allow_other_host: true
  end
end
