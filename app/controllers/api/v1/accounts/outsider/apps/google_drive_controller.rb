# OUTSIDER: Google Drive no bloco Google (Outsider::Apps::Google::Drive). Nenhum arquivo fica no Chatwoot. Mesmos
# endereços e respostas do OneDrive (MicrosoftDriveController), para a tela ser uma só.
#   GET    items             lista (view mine/shared/recent, folder_id, q, cursor)
#   GET    items/:id         o arquivo com a miniatura, para o painel ao lado
#   GET    items/:id/preview prévia para o visualizador
#   GET    items/:id/download   link assinado para baixar pelo Chatwoot
#   POST   items/:id/share   link do arquivo (scope anonymous = qualquer pessoa com o link)
#   POST   folders           nova pasta (parent_id, name)
#   POST   items             enviar arquivo (parent_id, file)
#   DELETE items/:id         para a Lixeira do Drive
class Api::V1::Accounts::Outsider::Apps::GoogleDriveController < Api::V1::Accounts::Outsider::Apps::BaseController
  MAX_UPLOAD = 250.megabytes

  before_action { require_google(:drive) }

  def index
    render json: drive.list(view: params[:view].presence || 'mine', folder_id: params[:folder_id], query: params[:q],
                            cursor: params[:cursor])
  rescue ::Outsider::Apps::Google::Client::Error => e
    graph_error(e)
  end

  def show
    render json: drive.details(nil, params[:id])
  rescue ::Outsider::Apps::Google::Client::Error => e
    graph_error(e)
  end

  def preview
    render json: drive.preview(nil, params[:id])
  rescue ::Outsider::Apps::Google::Client::Error => e
    graph_error(e)
  end

  def download
    render json: { url: drive.download_url(nil, params[:id]) }
  rescue ::Outsider::Apps::Google::Client::Error => e
    graph_error(e)
  end

  def share
    render json: { url: drive.share_link(nil, params[:id], scope: params[:scope]) }
  rescue ::Outsider::Apps::Google::Client::Error => e
    graph_error(e)
  end

  def create_folder
    return render_error_code('invalid', :unprocessable_entity) if params[:name].to_s.strip.blank?

    render json: drive.create_folder(nil, params[:parent_id], params[:name]), status: :created
  rescue ::Outsider::Apps::Google::Client::Error => e
    graph_error(e)
  end

  def create
    file = params[:file]
    return render_error_code('invalid', :unprocessable_entity) unless file.respond_to?(:original_filename)
    return render_error_code('too_big', :unprocessable_entity) if file.size > MAX_UPLOAD

    render json: drive.upload(nil, params[:parent_id], file), status: :created
  rescue ::Outsider::Apps::Google::Client::Error => e
    graph_error(e)
  end

  def destroy
    drive.delete(nil, params[:id])
    head :no_content
  rescue ::Outsider::Apps::Google::Client::Error => e
    graph_error(e)
  end

  private

  def drive
    @drive ||= ::Outsider::Apps::Google::Drive.new(google_link)
  end
end
