# OUTSIDER: conexões do bot com outros sistemas (Configurações > Automação por bot > Conexões), só para
# administradores. As senhas entram por aqui e nunca saem: a resposta só diz se cada uma está salva.
class Api::V1::Accounts::Outsider::BotConnectionsController < Api::V1::Accounts::BaseController
  Http = ::Outsider::Bot::Integrations::Http

  before_action :check_administrator
  before_action :find_connection, except: [:index, :create]

  # cada conexão com os fluxos que a usam
  def index
    usage = connection_usage
    render json: { payload: connections_scope.order(:name).map { |connection| connection.api_json.merge(flows: usage[connection.id] || []) } }
  end

  def create
    save(connections_scope.new(created_by_id: Current.user.id))
  end

  def update
    save(@connection)
  end

  # ainda usada em algum fluxo: pede confirmação (force) e mostra quais
  def destroy
    flows = connection_usage[@connection.id] || []
    if flows.any? && !ActiveModel::Type::Boolean.new.cast(params[:force])
      return render json: { error: 'in_use', flows: flows }, status: :unprocessable_entity
    end

    @connection.destroy!
    head :no_content
  end

  def test
    result = if @connection.nextcloud?
               test_nextcloud
             elsif @connection.postgres?
               test_postgres
             else
               test_http
             end
    record_test(result)
    render json: result
  end

  def folders
    render json: { payload: ::Outsider::Bot::Integrations::Nextcloud.new(@connection).folders(params[:path].to_s) }
  rescue Http::Error => e
    render json: { error: e.code, message: e.message.first(300) }, status: :unprocessable_entity
  end

  private

  def connections_scope
    ::Outsider::Bot::Connection.where(account_id: Current.account.id)
  end

  def find_connection
    @connection = connections_scope.find(params[:id])
  end

  def check_administrator
    return if Current.account_user&.administrator?

    render json: { error: 'forbidden' }, status: :forbidden
  end

  def save(connection)
    attributes = params.permit(:name, :kind, :base_url, :auth_type, :timeout_seconds, :allow_write)
    connection.assign_attributes(attributes.merge(updated_by_id: Current.user.id))
    # a connection string primeiro: o sslmode escolhido na tela (settings) vale mais que o padrão do servidor
    connection.connection_string = params[:connection_string] if params[:connection_string].present?
    connection.headers = Array(params[:headers]).map { |item| item.permit(:key, :value).to_h } if params.key?(:headers)
    connection.settings_input = params[:settings] if params[:settings].present?
    connection.secret_input = secret_params if params[:secrets].present?
    connection.save!
    render json: connection.api_json
  end

  def secret_params
    permitted = params[:secrets].permit(:api_key, :token, :password, :client_secret, headers: [:name, :value]).to_h
    permitted['headers'] = Array(permitted['headers']) if permitted.key?('headers')
    permitted
  end

  # { id da conexão => [{ id, name } dos fluxos com algum bloco nela] }
  def connection_usage
    ::Outsider::Bot::Flow.where(account_id: Current.account.id).order(:name).each_with_object({}) do |flow, usage|
      Array(flow.graph['nodes']).filter_map { |node| node.dig('data', 'connection_id').to_i.nonzero? }.uniq.each do |id|
        (usage[id] ||= []) << { id: flow.id, name: flow.name }
      end
    end
  end

  def test_http
    response = Http.new(@connection).call('GET', @connection.settings['test_path'].to_s)
    { ok: response.success?, status: response.status, duration_ms: response.duration_ms, url: response.url,
      excerpt: ::Outsider::Bot::Log.excerpt(response.body) }
  rescue Http::Error => e
    { ok: false, error: e.code, message: e.message.first(300) }
  end

  def test_nextcloud
    result = ::Outsider::Bot::Integrations::Nextcloud.new(@connection).test
    if result['user_id'].present? && result['user_id'] != @connection.settings['user_id']
      @connection.update_columns(settings: @connection.settings.merge('user_id' => result['user_id'])) # rubocop:disable Rails/SkipsModelValidations
    end
    { ok: true, folder: result['folder'], entries: result['entries'] }
  rescue Http::Error => e
    { ok: false, error: e.code, message: e.message.first(300) }
  end

  def test_postgres
    result = ::Outsider::Bot::Integrations::Postgres.new(@connection).test
    { ok: true, database: result['database'], user: result['user'], version: result['version'], duration_ms: result['duration_ms'] }
  rescue Http::Error => e
    { ok: false, error: e.code, message: e.message.first(300) }
  end

  def record_test(result)
    ::Outsider::Bot::Log.record(account_id: Current.account.id, connection_id: @connection.id, kind: 'test', status: result[:ok] ? 'ok' : 'error',
                                http_status: result[:status], duration_ms: result[:duration_ms],
                                detail: { 'url' => result[:url], 'error' => result[:error], 'message' => result[:message], 'test' => true }.compact)
  end
end
