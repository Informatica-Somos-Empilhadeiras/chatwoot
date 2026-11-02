# OUTSIDER: Telefonia > URA (Entrega 26), só para administradores: as URAs da conta, o editor de fluxograma e os
# áudios dos blocos. O desenho é limpo pelo Outsider::Voice::IvrGraph ao salvar; options traz o que o editor
# oferece (números da conta, vendedores com ramal, filiais e se a voz natural da OpenAI está ligada).
class Api::V1::Accounts::Outsider::Crm::IvrFlowsController < Api::V1::Accounts::Outsider::Crm::BaseController
  AUDIO_EXTENSIONS = %w[mp3 wav ogg oga opus m4a aac webm flac].freeze

  before_action :ensure_crm_admin
  before_action :find_flow, only: [:show, :update, :destroy, :audios]

  def index
    render json: { payload: flows_scope.order(:id).map { |flow| summary(flow) }, options: options }
  end

  def show
    render json: detail(@flow)
  end

  def create
    flow = flows_scope.create!(name: params[:name].presence || I18n.t('outsider_voice.ivr.default_name'), active: false,
                               graph: starter_graph, updated_by_id: Current.user.id)
    render json: detail(flow)
  end

  def update
    attributes = params.permit(:name, :active, numbers: []).merge(updated_by_id: Current.user.id)
    attributes[:graph] = graph_param if params.key?(:graph)
    @flow.update!(attributes)
    render json: detail(@flow)
  end

  def destroy
    @flow.destroy!
    head :no_content
  end

  # áudio de um bloco (enviado do computador ou gravado no navegador): fica no fluxo, o bloco guarda só o id
  def audios
    file = params[:file]
    return render(json: { error: 'no_file' }, status: :unprocessable_entity) unless file.respond_to?(:original_filename)
    return render(json: { error: 'file_too_big' }, status: :unprocessable_entity) if file.size > ::Outsider::Voice::IvrFlow::MAX_AUDIO
    return render(json: { error: 'file_type' }, status: :unprocessable_entity) unless audio?(file)

    blob = ActiveStorage::Blob.create_and_upload!(io: file, filename: file.original_filename, content_type: file.content_type)
    @flow.audios.attach(blob)
    render json: audio_json(blob)
  end

  private

  def flows_scope
    ::Outsider::Voice::IvrFlow.where(account_id: Current.account.id)
  end

  def find_flow
    @flow = flows_scope.find(params[:id])
  end

  def audio?(file)
    extension = File.extname(file.original_filename.to_s).delete('.').downcase
    AUDIO_EXTENSIONS.include?(extension) && file.content_type.to_s.start_with?('audio/', 'video/webm')
  end

  # o desenho vem como JSON livre; quem limpa é o Outsider::Voice::IvrGraph
  def graph_param
    raw = params[:graph]
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    raw.is_a?(Hash) ? raw : {}
  end

  # URA nova: boas-vindas, menu com duas opções e recado se ninguém atender
  def starter_graph
    texts = I18n.t('outsider_voice.ivr.starter')
    nodes = [
      { 'id' => 'start', 'type' => 'start', 'x' => 40, 'y' => 160, 'data' => {} },
      { 'id' => 'welcome', 'type' => 'say', 'x' => 360, 'y' => 160, 'data' => { 'prompt' => { 'text' => texts[:welcome] } } },
      { 'id' => 'menu', 'type' => 'menu', 'x' => 680, 'y' => 120, 'data' => {
        'label' => texts[:menu_label], 'prompt' => { 'text' => texts[:menu] }, 'invalid_prompt' => { 'text' => texts[:invalid] },
        'options' => [{ 'id' => 'sales', 'digit' => '1', 'label' => texts[:sales] },
                      { 'id' => 'support', 'digit' => '2', 'label' => texts[:support] }]
      } },
      { 'id' => 'transfer', 'type' => 'transfer', 'x' => 1000, 'y' => 120, 'data' => { 'prompt' => { 'text' => texts[:wait] } } },
      { 'id' => 'voicemail', 'type' => 'voicemail', 'x' => 1320, 'y' => 160, 'data' => { 'prompt' => { 'text' => texts[:voicemail] } } },
      { 'id' => 'bye', 'type' => 'hangup', 'x' => 1640, 'y' => 160, 'data' => { 'prompt' => { 'text' => texts[:bye] } } }
    ]
    edges = [%w[start next welcome], %w[welcome next menu], %w[menu sales transfer], %w[menu support transfer], %w[menu invalid transfer],
             %w[transfer no_answer voicemail], %w[voicemail next bye]].map do |from, port, to|
      { 'id' => "e_#{from}_#{port}", 'from' => from,
        'port' => port, 'to' => to }
    end
    { 'nodes' => nodes, 'edges' => edges }
  end

  def options
    settings = ::Outsider::Voice::Settings.new(Current.account)
    agents = settings.enabled_agents
    {
      numbers: settings.numbers.map { |row| row.slice('number', 'state', 'label') },
      people: User.where(id: agents.keys).order(:name).map { |user| { id: user.id, name: user.name, extension: agents[user.id]['extension'] } },
      branches: settings.branches, natural_voice: ::Outsider::Voice::Speech.new(Current.account).available?,
      voices: ::Outsider::Voice::IvrGraph::VOICES
    }
  end

  def summary(flow)
    flow.slice(:id, :name, :active, :numbers, :updated_at).merge(blocks: flow.graph_object.nodes.size)
  end

  def detail(flow)
    summary(flow).merge(graph: flow.graph, audios: flow.audios_blobs.map { |blob| audio_json(blob) }, options: options)
  end

  def audio_json(blob)
    { id: blob.id, filename: blob.filename.to_s, byte_size: blob.byte_size, url: rails_blob_path(blob, only_path: true) }
  end
end
