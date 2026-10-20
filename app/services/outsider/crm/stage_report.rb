# OUTSIDER: funil de um pipeline, etapa por etapa.
#
# - Agora: negócios abertos em cada etapa, valor e ponderado. É a mesma conta das colunas do Kanban
#   com os mesmos filtros, para quem quiser conferir na mão.
# - Conversão: dos negócios criados no período, quantos passaram por cada etapa e quantos seguiram
#   para a próxima. "Passou" vem do histórico de etapas da auditoria (audited): conta a etapa mais
#   adiantada que o negócio já alcançou; ganho conta como tendo passado por todas.
# - Tempo médio: quanto tempo os negócios ficaram em cada etapa, pelas saídas de etapa dentro do
#   período (mudança de etapa, ganho, perda ou encaminhamento). "Parados agora" é a média de dias
#   na etapa atual dos abertos.
#
# Lê no máximo LIMIT negócios do período (os mais recentes) e uma consulta indexada na auditoria
# (auditable_type + auditable_id). Se passar do limite, a resposta traz truncated: true.
class Outsider::Crm::StageReport
  LIMIT = 5000
  DEAL_COLUMNS = %i[id status stage_id created_at closed_at].freeze

  def initialize(scope, pipeline:, period:)
    @scope = scope.where(pipeline_id: pipeline.id)
    @pipeline = pipeline
    @range = period.range
    @stages = pipeline.stages.select(&:kind_open?)
    @index = @stages.each_with_index.to_h { |stage, index| [stage.id, index] }
  end

  def to_h
    reached = reached_counts
    won = cohort.count { |deal| deal[:status] == 'won' }
    {
      pipeline_id: @pipeline.id, pipeline_name: @pipeline.name, business_unit_id: @pipeline.business_unit_id,
      cohort_count: cohort.size, truncated: deals.size >= LIMIT,
      stages: @stages.each_with_index.map { |stage, index| stage_row(stage, index, reached) },
      won: { count: won, conversion_rate: rate(won, reached.last.to_i) }
    }
  end

  private

  def stage_row(stage, index, reached)
    stage.slice(:id, :name, :color, :probability, :sla_hours).symbolize_keys.merge(now_row(stage.id), flow_row(stage.id, index, reached))
  end

  def now_row(stage_id)
    count, value, weighted, age = now_rows[stage_id]
    { open_count: count.to_i, open_value_cents: value.to_i, weighted_value_cents: weighted.to_f.round,
      current_average_days: age && (age.to_f / 1.day).round(1) }
  end

  def flow_row(stage_id, index, reached)
    durations = stage_durations[stage_id] || []
    { reached_count: reached[index], conversion_rate: index.zero? ? nil : rate(reached[index], reached[index - 1]),
      average_days: durations.empty? ? nil : (durations.sum / durations.size / 1.day).round(1), exits_count: durations.size }
  end

  def now_rows
    @now_rows ||= @scope.open.joins(:stage).group(:stage_id)
                        .pluck(:stage_id, Outsider::Crm::Report::COUNT_SQL, Outsider::Crm::Report::VALUE_SQL,
                               Outsider::Crm::Report::WEIGHTED_SUM_SQL, stage_age_sql)
                        .to_h { |stage_id, *values| [stage_id, values] }
  end

  def stage_age_sql
    Arel.sql(Outsider::Crm::Opportunity.sanitize_sql_array(
               ['AVG(EXTRACT(EPOCH FROM (?::timestamp - outsider_crm_opportunities.stage_changed_at)))', Time.current]
             ))
  end

  # Negócios do pipeline que existiam no período: criados até o fim dele e abertos ou fechados depois do início
  def deals
    @deals ||= @scope.where(created_at: ..@range.end)
                     .where('outsider_crm_opportunities.status = 0 OR outsider_crm_opportunities.closed_at >= ?', @range.begin)
                     .order(id: :desc).limit(LIMIT)
                     .pluck(*DEAL_COLUMNS).map { |row| DEAL_COLUMNS.zip(row).to_h }
  end

  def cohort
    @cohort ||= deals.select { |deal| @range.cover?(deal[:created_at]) }
  end

  # Para cada etapa, quantos negócios do período chegaram nela ou mais adiante
  def reached_counts
    counts = Array.new(@stages.size, 0)
    cohort.each do |deal|
      furthest = deal[:status] == 'won' ? @stages.size - 1 : timeline(deal).filter_map { |_at, stage_id| @index[stage_id] }.max
      (0..furthest).each { |index| counts[index] += 1 } if furthest
    end
    counts
  end

  # Durações (em segundos) das passagens pelas etapas abertas que terminaram dentro do período
  def stage_durations
    @stage_durations ||= deals.flat_map { |deal| passages(deal) }.group_by(&:first).transform_values { |rows| rows.map(&:last) }
  end

  # [[etapa, segundos nela], ...] das passagens por etapa aberta que terminaram no período. Fechado
  # ainda numa etapa aberta (encaminhado, ou pipeline sem etapa de ganho/perda): termina no fechamento.
  def passages(deal)
    entries = timeline(deal)
    entries << [deal[:closed_at], nil] if deal[:closed_at] && @index.key?(entries.last.last)
    entries.each_cons(2).filter_map do |(entered_at, stage_id), (left_at, _next)|
      [stage_id, left_at - entered_at] if @index.key?(stage_id) && @range.cover?(left_at)
    end
  end

  # [[quando entrou, etapa], ...] em ordem, pela auditoria. Sem histórico, fica a etapa atual desde a criação.
  def timeline(deal)
    entries = (histories[deal[:id]] || []).each_with_object([]) do |(at, change), list|
      if change.is_a?(Array)
        list << [deal[:created_at], change.first] if list.empty?
        list << [at, change.last]
      else
        list << [at, change]
      end
    end
    entries.presence || [[deal[:created_at], deal[:stage_id]]]
  end

  def histories
    @histories ||= Audited::Audit.where(auditable_type: Outsider::Crm::Opportunity.name, auditable_id: deals.pluck(:id))
                                 .where(Arel.sql("(audited_changes -> 'stage_id') IS NOT NULL"))
                                 .order(:auditable_id, :version)
                                 .pluck(:auditable_id, :created_at, Arel.sql("audited_changes -> 'stage_id'"))
                                 .group_by(&:first)
                                 .transform_values { |rows| rows.map { |_id, at, change| [at, decode(change)] } }
  end

  def decode(change)
    change.is_a?(String) ? JSON.parse(change) : change
  end

  def rate(part, total)
    total.to_i.zero? ? nil : (part * 100.0 / total).round(1)
  end
end
