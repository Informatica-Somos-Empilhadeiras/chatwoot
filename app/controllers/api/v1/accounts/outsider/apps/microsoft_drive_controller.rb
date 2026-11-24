# OUTSIDER: OneDrive no bloco Microsoft (Outsider::Apps::Microsoft::Drive). Nenhum arquivo fica no Chatwoot.
#   GET    items             lista (view mine/shared/recent, drive_id, folder_id, q, cursor)
#   GET    items/:id         o arquivo com a miniatura, para o painel ao lado (drive_id)
#   GET    items/:id/preview prévia para o visualizador (drive_id)
#   GET    items/:id/download   endereço temporário da Microsoft para baixar
#   POST   items/:id/share   link para compartilhar (scope organization/anonymous)
#   POST   folders           nova pasta (drive_id, parent_id, name)
#   POST   items             enviar arquivo (drive_id, parent_id, file)
#   DELETE items/:id         para a Lixeira do OneDrive
class Api::V1::Accounts::Outsider::Apps::MicrosoftDriveController < Api::V1::Accounts::Outsider::Apps::BaseController
  MAX_UPLOAD = 250.megabytes

  before_action { require_microsoft }

  def index
    render json: drive.list(view: params[:view].presence || 'mine', drive_id: params[:drive_id], folder_id: params[:folder_id],
                            query: params[:q], cursor: params[:cursor])
  rescue ::Outsider::Teams::Graph::Client::Error => e
    graph_error(e)
  end

  def show
    render json: drive.details(params[:drive_id], params[:id])
  rescue ::Outsider::Teams::Graph::Client::Error => e
    graph_error(e)
  end

  def preview
    render json: drive.preview(params[:drive_id], params[:id])
  rescue ::Outsider::Teams::Graph::Client::Error => e
    graph_error(e)
  end

  def download
    render json: { url: drive.download_url(params[:drive_id], params[:id]) }
  rescue ::Outsider::Teams::Graph::Client::Error => e
    graph_error(e)
  end

  def share
    render json: { url: drive.share_link(params[:drive_id], params[:id], scope: params[:scope]) }
  rescue ::Outsider::Teams::Graph::Client::Error => e
    graph_error(e)
  end

  def create_folder
    return render_error_code('invalid', :unprocessable_entity) if params[:name].to_s.strip.blank?

    render json: drive.create_folder(params[:drive_id], params[:parent_id], params[:name]), status: :created
  rescue ::Outsider::Teams::Graph::Client::Error => e
    graph_error(e)
  end

  def create
    file = params[:file]
    return render_error_code('invalid', :unprocessable_entity) unless file.respond_to?(:original_filename)
    return render_error_code('too_big', :unprocessable_entity) if file.size > MAX_UPLOAD

    render json: drive.upload(params[:drive_id], params[:parent_id], file), status: :created
  rescue ::Outsider::Teams::Graph::Client::Error => e
    graph_error(e)
  end

  def destroy
    drive.delete(params[:drive_id], params[:id])
    head :no_content
  rescue ::Outsider::Teams::Graph::Client::Error => e
    graph_error(e)
  end

  private

  def drive
    @drive ||= ::Outsider::Apps::Microsoft::Drive.new(microsoft_link)
  end
end
