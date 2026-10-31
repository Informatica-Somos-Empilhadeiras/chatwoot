# OUTSIDER: fluxos do bot (Configurações > Automação por bot), só para administradores.
# O desenho é limpo pelo Outsider::Bot::Graph ao salvar.
class Api::V1::Accounts::Outsider::BotFlowsController < Api::V1::Accounts::BaseController
  before_action :check_administrator
  before_action :find_flow, except: [:index, :create, :run_block]

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
                                                 graph: params[:graph].present? ? graph_param : starter_graph(params[:template])))
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

  # Testar do editor: roda um bloco de integração com variáveis de exemplo, sem mandar nada a cliente
  # nenhum. O que altera dados (POST, PUT, PATCH, DELETE, mutation do GraphQL, INSERT/UPDATE/DELETE no banco)
  # numa conexão que permite alterar só roda com confirm_write; antes disso a tela pergunta.
  def run_block
    node = test_node
    return render(json: { error: 'invalid_block' }, status: :unprocessable_entity) unless node
    return render(json: { needs_confirmation: true }) if needs_confirmation?(node)

    template = ::Outsider::Bot::Template.new(test_variables, contact: test_contact, conversation: { 'id' => 0, 'numero' => 0 })
    return render(json: doc_send_preview(node)) if node['type'] == 'doc_send'

    runner = ::Outsider::Bot::Integrations::BlockRunner.new(
      account: Current.account, template: template, context: { test: true, flow_id: params[:flow_id].presence&.to_i, read_only: !confirm_write? }
    )
    result = runner.run(node)
    return render(json: { needs_confirmation: true }) if write_blocked?(node, result)

    render json: { port: result.port, variables: result.variables, choice: result.choice, response: response_json(result.response, runner) }
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

  def test_node
    raw = params[:node]
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    node = ::Outsider::Bot::Graph.sanitize('nodes' => [raw.to_h.merge('x' => 0, 'y' => 0)], 'edges' => [])['nodes'].first
    node if node && ::Outsider::Bot::IntegrationGraph::TYPES.include?(node['type'])
  end

  def needs_confirmation?(node)
    return false if confirm_write? || node['type'] != 'api' || !writable_connection?(node)

    data = node['data']
    return ::Outsider::Bot::Integrations::ApiCall.graphql_write?(data['graphql_query']) if data['body_type'] == 'graphql'

    ::Outsider::Bot::Integrations::Http::WRITE_METHODS.include?(data['method'])
  end

  # o banco só diz que o SQL altera dados quando tenta: o teste roda só leitura e, se esbarrar nisso, pergunta
  def write_blocked?(node, result)
    node['type'] == 'db_query' && !confirm_write? && result.variables['erro'] == 'write_not_allowed' && writable_connection?(node)
  end

  def writable_connection?(node)
    ::Outsider::Bot::Connection.exists?(account_id: Current.account.id, id: node.dig('data', 'connection_id'), allow_write: true)
  end

  def confirm_write?
    ActiveModel::Type::Boolean.new.cast(params[:confirm_write])
  end

  def test_variables
    raw = params[:variables]
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    variables = raw.is_a?(Hash) ? raw.deep_stringify_keys : {}
    variables.to_json.bytesize > 256.kilobytes ? {} : variables
  end

  def test_contact
    given = params[:contact].respond_to?(:permit) ? params[:contact].permit(:nome, :telefone, :email).to_h : {}
    name = given['nome'].presence || 'Maria Souza'
    { 'nome' => name, 'primeiro_nome' => name.split.first, 'telefone' => given['telefone'].presence || '+5511987654321',
      'email' => given['email'].presence || 'maria@exemplo.com.br', 'empresa' => '', 'cidade' => '', 'id' => 0 }
  end

  def doc_send_preview(node)
    doc = test_variables[node.dig('data', 'source')]
    return { port: 'error', variables: { 'erro' => 'no_document' } } unless doc.is_a?(Hash) && doc['caminho'].present?

    { port: 'ok', variables: {}, preview: { name: doc['nome'], mode: node.dig('data', 'mode') } }
  end

  def response_json(response, runner)
    return unless response

    data = response.data
    { status: response.status, duration_ms: response.duration_ms, url: response.url, cached: response.cached || false,
      content_type: response.content_type, json: data.nil? ? nil : runner.capped(data),
      text: data.nil? ? response.body.to_s.first(4000) : nil }
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
  # template: 'document' = exemplo da 2ª via de documento; sem template = o começo de sempre
  def starter_graph(template)
    I18n.with_locale(Current.account.locale.presence || I18n.default_locale) do
      template.to_s == 'document' ? ::Outsider::Bot::Starter.document_graph : ::Outsider::Bot::Starter.graph
    end
  end
end
