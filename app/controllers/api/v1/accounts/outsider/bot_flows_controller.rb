# OUTSIDER: fluxos do bot (Configurações > Automação por bot), só para administradores.
# O desenho é limpo pelo Outsider::Bot::Graph ao salvar.
class Api::V1::Accounts::Outsider::BotFlowsController < Api::V1::Accounts::BaseController
  before_action :check_administrator
  before_action :find_flow, except: [:index, :create]

  def index
    flows = flows_scope.order(:id).to_a
    stats = session_stats(flows.map(&:id))
    render json: { payload: flows.map { |flow| summary(flow, stats) } }
  end

  def show
    render json: detail(@flow)
  end

  def create
    flow = flows_scope.create!(flow_params.merge(created_by_id: Current.user.id, updated_by_id: Current.user.id,
                                                 graph: params[:graph].present? ? graph_param : starter_graph))
    render json: detail(flow)
  end

  def update
    attributes = flow_params.merge(updated_by_id: Current.user.id)
    attributes[:graph] = graph_param if params.key?(:graph)
    @flow.update!(attributes)
    render json: detail(@flow)
  end

  def duplicate
    copy = flows_scope.create!(name: "#{@flow.name} (cópia)".first(120), active: false, inbox_ids: @flow.inbox_ids,
                               graph: @flow.graph, created_by_id: Current.user.id, updated_by_id: Current.user.id)
    render json: detail(copy)
  end

  def destroy
    @flow.destroy!
    head :no_content
  end

  private

  def flows_scope
    ::Outsider::Bot::Flow.where(account_id: Current.account.id)
  end

  def find_flow
    @flow = flows_scope.find(params[:id])
  end

  def check_administrator
    return if Current.account_user&.administrator?

    render json: { error: 'forbidden' }, status: :forbidden
  end

  def flow_params
    permitted = params.permit(:name, :active, inbox_ids: [])
    permitted[:inbox_ids] = Array(permitted[:inbox_ids]).map(&:to_i) & Current.account.inboxes.pluck(:id) if permitted.key?(:inbox_ids)
    permitted
  end

  # o desenho vem como JSON livre; quem limpa é o Outsider::Bot::Graph
  def graph_param
    raw = params[:graph]
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    raw.is_a?(Hash) ? raw : {}
  end

  def session_stats(flow_ids)
    ::Outsider::Bot::Session.where(flow_id: flow_ids).where('created_at > ?', 7.days.ago)
                            .group(:flow_id, :status).count
  end

  def summary(flow, stats)
    counts = stats.select { |(flow_id, _), _| flow_id == flow.id }.transform_keys(&:last)
    {
      id: flow.id, name: flow.name, active: flow.active, inbox_ids: flow.inbox_ids,
      trigger: flow.graph_object.start&.dig('data', 'trigger'), nodes_count: flow.graph_object.nodes.size,
      updated_at: flow.updated_at.to_i,
      stats: { started: counts.values.sum, handed_off: counts['handed_off'].to_i, finished: counts['finished'].to_i }
    }
  end

  def detail(flow)
    { id: flow.id, name: flow.name, active: flow.active, inbox_ids: flow.inbox_ids, graph: flow.graph, updated_at: flow.updated_at.to_i }
  end

  # fluxo novo já vem com um começo: boas-vindas, menu de 3 opções e passar para a equipe
  def starter_graph
    I18n.with_locale(Current.account.locale.presence || I18n.default_locale) { ::Outsider::Bot::Starter.graph }
  end
end
