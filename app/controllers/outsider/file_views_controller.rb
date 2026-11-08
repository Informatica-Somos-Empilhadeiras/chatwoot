# OUTSIDER: endereço temporário (15 minutos, assinado) de um anexo para o visualizador de documentos: o navegador abre
# PDF e texto aqui dentro de uma janela do Chatwoot, e o visualizador do Office na web busca Word, Excel e PowerPoint.
# Entrega o mesmo arquivo do anexo, para ver (inline), sem criar cópia.
class Outsider::FileViewsController < ActionController::API
  def show
    attachment = Outsider::FileView.attachment_for(params[:token])
    return head(:not_found) unless attachment&.file&.attached?

    view = Outsider::FileView.new(attachment)
    response.headers['Cache-Control'] = 'private, max-age=300'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    attachment.file.blob.open do |file|
      send_data file.read, type: view.content_type, disposition: 'inline', filename: view.safe_filename
    end
  end
end
