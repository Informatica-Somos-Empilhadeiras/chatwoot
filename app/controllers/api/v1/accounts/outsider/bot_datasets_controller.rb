# OUTSIDER: planilhas do bot (Configurações > Automação por bot > Planilhas), só para administradores. O
# navegador lê o Excel ou o CSV e manda as linhas em pedaços (rows); finish troca a planilha de uma vez, então
# o bot continua usando a anterior até o envio terminar.
class Api::V1::Accounts::Outsider::BotDatasetsController < Api::V1::Accounts::BaseController
  Dataset = ::Outsider::Bot::Dataset
  PREVIEW_ROWS = 50

  before_action :check_administrator
  before_action :find_dataset, except: [:index, :create]

  def index
    render json: { payload: datasets_scope.order(:name).map(&:api_json) }
  end

  # as primeiras linhas, ou as que têm o texto procurado (q) em qualquer coluna
  def show
    rows = @dataset.rows.order(:position)
    folded = ::Outsider::Bot::DatasetRow.fold(params[:q])
    rows = rows.where('EXISTS (SELECT 1 FROM jsonb_each_text(folded) AS cell(key, value) WHERE cell.value LIKE ?)', "%#{folded}%") if folded.present?
    render json: @dataset.api_json.merge(rows: rows.limit(PREVIEW_ROWS).pluck(:data), matches: folded.present? ? rows.count : @dataset.rows_count)
  end

  def create
    dataset = datasets_scope.create!(name: params[:name], created_by_id: Current.user.id, updated_by_id: Current.user.id)
    render json: dataset.api_json
  end

  def update
    @dataset.update!(name: params[:name], updated_by_id: Current.user.id)
    render json: @dataset.api_json
  end

  def destroy
    @dataset.destroy!
    head :no_content
  end

  # um pedaço do envio: { generation, offset, columns: [rótulos], rows: [[células], ...] }. O primeiro pedaço
  # vai sem generation: o servidor escolhe uma nova e devolve, e os outros pedaços mandam a mesma.
  def rows
    cells = Array(request.request_parameters['rows']).first(Dataset::CHUNK_ROWS)
    offset = params[:offset].to_i
    generation = params[:generation].to_i
    generation = next_generation if generation <= 0 && offset.zero?
    return render_error('invalid_generation') unless generation.positive? && generation != @dataset.generation
    return render_error('too_many_rows') if offset.negative? || offset + cells.size > Dataset::MAX_ROWS

    @dataset.touch if offset.zero? # rubocop:disable Rails/SkipsModelValidations
    records = build_rows(Dataset.build_columns(request.request_parameters['columns']), cells, generation, offset)
    ::Outsider::Bot::DatasetRow.insert_all(records) if records.any? # rubocop:disable Rails/SkipsModelValidations
    render json: { received: records.size, generation: generation }
  end

  def finish
    generation = params[:generation].to_i
    count = @dataset.all_rows.where(generation: generation).count
    return render_error('empty_upload') if generation <= 0 || count.zero?

    @dataset.update!(generation: generation, rows_count: count, columns: Dataset.build_columns(request.request_parameters['columns']),
                     file_name: params[:file_name].to_s.first(200), updated_by_id: Current.user.id)
    @dataset.all_rows.where.not(generation: generation).in_batches(of: 5000).delete_all
    render json: @dataset.api_json
  end

  # Testar do bloco Planilha
  def lookup
    row = ::Outsider::Bot::Integrations::DatasetLookup.new(@dataset).find(column: params[:column].to_s, operator: params[:operator].to_s,
                                                                          value: params[:value].to_s)
    render json: { row: row }
  end

  private

  def datasets_scope
    Dataset.where(account_id: Current.account.id)
  end

  def find_dataset
    @dataset = datasets_scope.find(params[:id])
  end

  def check_administrator
    return if Current.account_user&.administrator?

    render json: { error: 'forbidden' }, status: :forbidden
  end

  def next_generation
    [@dataset.all_rows.maximum(:generation).to_i, @dataset.generation].max + 1
  end

  def render_error(code)
    render json: { error: code }, status: :unprocessable_entity
  end

  def build_rows(columns, cells, generation, offset)
    cells.each_with_index.filter_map do |row, index|
      data = columns.each_with_index.to_h { |column, position| [column['key'], Array(row)[position].to_s.strip.first(Dataset::MAX_CELL)] }
                    .compact_blank
      next if data.empty?

      { dataset_id: @dataset.id, generation: generation, position: offset + index, data: data,
        folded: data.transform_values { |value| ::Outsider::Bot::DatasetRow.fold(value) } }
    end
  end
end
