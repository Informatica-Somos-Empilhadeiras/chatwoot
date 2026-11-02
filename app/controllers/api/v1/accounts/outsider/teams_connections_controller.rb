# OUTSIDER: Configurações > Microsoft Teams (Entrega 26), só administradores. Ligar um robô do Teams cria uma caixa de
# entrada (tipo API) com a pessoa que ligou como agente; as outras pessoas entram pela tela de caixas do Chatwoot.
# test confere o app_id, o segredo e o locatário pedindo um token à Microsoft; manifest baixa o pacote do aplicativo
# para enviar no Teams. Desligar apaga só a ligação: a caixa e as conversas continuam.
class Api::V1::Accounts::Outsider::TeamsConnectionsController < Api::V1::Accounts::BaseController
  before_action :check_administrator
  before_action :find_connection, only: [:update, :destroy, :test, :manifest]

  rescue_from ActiveRecord::RecordInvalid do |error|
    render json: { error: 'invalid', message: error.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  def index
    render json: { payload: connections.includes(:inbox).order(:id).map { |connection| connection_json(connection) } }
  end

  def create
    connection = ActiveRecord::Base.transaction do
      channel = Channel::Api.create!(account: Current.account)
      inbox = Current.account.inboxes.create!(name: params.require(:name).to_s.strip.first(100), channel: channel)
      inbox.inbox_members.create!(user: Current.user)
      connections.create!(credentials.merge(inbox: inbox))
    end
    render json: connection_json(connection), status: :created
  end

  # segredo em branco: continua o guardado
  def update
    @connection.update!(credentials)
    render json: connection_json(@connection)
  end

  def destroy
    @connection.destroy!
    head :no_content
  end

  def test
    ::Outsider::Teams::Auth.new(@connection).access_token
    render json: { ok: true }
  rescue ::Outsider::Teams::Auth::Invalid => e
    render json: { ok: false, message: e.message }, status: :unprocessable_entity
  end

  def manifest
    package = ::Outsider::Teams::AppPackage.new(@connection, site: site)
    send_data package.to_zip, filename: package.filename, type: 'application/zip'
  end

  private

  def connections
    ::Outsider::TeamsConnection.where(account_id: Current.account.id)
  end

  def find_connection
    @connection = connections.find(params[:id])
  end

  def check_administrator
    render json: { error: 'forbidden' }, status: :forbidden unless Current.account_user&.administrator?
  end

  def credentials
    attributes = params.permit(:app_id, :tenant_id).to_h.transform_values { |value| value.to_s.strip.downcase }
    attributes[:app_password] = params[:app_password].to_s if params[:app_password].present?
    attributes.merge(account: Current.account)
  end

  def connection_json(connection)
    {
      id: connection.id, app_id: connection.app_id, tenant_id: connection.tenant_id, inbox_id: connection.inbox_id,
      inbox_name: connection.inbox.name, last_activity_at: connection.last_activity_at, created_at: connection.created_at,
      messaging_endpoint: "#{site}#{connection.messaging_path}"
    }
  end

  def site
    ENV.fetch('FRONTEND_URL', request.base_url).chomp('/')
  end
end
