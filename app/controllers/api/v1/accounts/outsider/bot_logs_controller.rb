# OUTSIDER: registro das chamadas do bot a outros sistemas (Configurações > Automação por bot > Registro),
# só para administradores. Os mais novos primeiro, de 50 em 50 (before_id pega os anteriores).
class Api::V1::Accounts::Outsider::BotLogsController < Api::V1::Accounts::BaseController
  PER_PAGE = 50
  FILTERS = { status: %w[ok error not_found], kind: %w[api sheet doc_search doc_send file_send db_query test] }.freeze

  before_action :check_administrator

  def index
    page = logs.limit(PER_PAGE + 1).to_a
    more = page.size > PER_PAGE
    page = page.first(PER_PAGE)
    names = related_names(page)
    render json: { payload: page.map { |log| serialize(log, names) }, next_before_id: more ? page.last.id : nil }
  end

  private

  def check_administrator
    return if Current.account_user&.administrator?

    render json: { error: 'forbidden' }, status: :forbidden
  end

  def logs
    scope = ::Outsider::Bot::Log.where(account_id: Current.account.id).order(id: :desc)
    FILTERS.each { |key, values| scope = scope.where(key => params[key]) if values.include?(params[key]) }
    scope = scope.where(flow_id: params[:flow_id]) if params[:flow_id].present?
    scope = scope.where(connection_id: params[:connection_id]) if params[:connection_id].present?
    scope = scope.where('id < ?', params[:before_id].to_i) if params[:before_id].present?
    scope
  end

  def related_names(page)
    account_id = Current.account.id
    {
      flows: ::Outsider::Bot::Flow.where(account_id: account_id, id: page.filter_map(&:flow_id).uniq).pluck(:id, :name).to_h,
      connections: ::Outsider::Bot::Connection.where(account_id: account_id, id: page.filter_map(&:connection_id).uniq).pluck(:id, :name).to_h,
      conversations: Current.account.conversations.where(id: page.filter_map(&:conversation_id).uniq).pluck(:id, :display_id).to_h
    }
  end

  def serialize(log, names)
    {
      id: log.id, created_at: log.created_at.to_i, kind: log.kind, status: log.status, http_status: log.http_status,
      duration_ms: log.duration_ms, node_id: log.node_id, detail: log.detail,
      flow: log.flow_id && { id: log.flow_id, name: names[:flows][log.flow_id] },
      connection: log.connection_id && { id: log.connection_id, name: names[:connections][log.connection_id] },
      conversation_display_id: names[:conversations][log.conversation_id]
    }
  end
end
