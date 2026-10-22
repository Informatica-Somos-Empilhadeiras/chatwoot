# OUTSIDER: seção "Propostas" da aba Relatórios (Entrega 18). Conta as propostas emitidas no período
# (data de emissão) que a pessoa pode ver, pela situação de agora. Tudo por agregação no banco.
# - vencida: rascunho ou enviada com a validade passada (não é uma situação gravada);
# - taxa de aceite: aceitas / (aceitas + recusadas + vencidas). Em aberto e rascunho não entram;
# - tempo até a resposta: média de dias entre o envio e o aceite ou a recusa;
# - canceladas aparecem só na contagem delas, fora de valores e taxas.
class Outsider::Crm::ProposalReport
  TABLE = 'outsider_crm_proposals'.freeze
  BUCKETS = %w[draft open expired accepted rejected canceled].freeze
  COUNT_SQL = Arel.sql('COUNT(*)')
  VALUE_SQL = Arel.sql("COALESCE(SUM(#{TABLE}.total_cents), 0)")
  TOP_PRODUCTS = 10
  PRODUCT_KEY_SQL = Arel.sql('COALESCE(outsider_crm_proposal_items.product_id::text, LOWER(outsider_crm_proposal_items.description))')

  def initialize(scope, period:)
    @scope = scope.where(issued_on: period.range.begin.to_date..period.range.end.to_date)
    @period = period
  end

  def to_h
    { period: @period.as_json, summary: summary, owners: owners, products: products }
  end

  private

  def bucket_sql
    @bucket_sql ||= Arel.sql(Outsider::Crm::Proposal.sanitize_sql_array([<<~SQL.squish, Time.zone.today]))
      CASE WHEN #{TABLE}.status IN (0, 1) AND #{TABLE}.valid_until < ? THEN 'expired'
           WHEN #{TABLE}.status = 0 THEN 'draft' WHEN #{TABLE}.status = 1 THEN 'open'
           WHEN #{TABLE}.status = 2 THEN 'accepted' WHEN #{TABLE}.status = 3 THEN 'rejected' ELSE 'canceled' END
    SQL
  end

  def summary
    row = totals(@scope.group(bucket_sql).pluck(bucket_sql, COUNT_SQL, VALUE_SQL))
    row.merge(average_days_to_decision: average_days(@scope), sent_count: @scope.where.not(sent_at: nil).where.not(status: :canceled).count)
  end

  def totals(rows)
    data = rows.to_h { |bucket, count, value| [bucket, [count, value.to_i]] }
    row = BUCKETS.each_with_object({}) do |bucket, result|
      count, value = data.fetch(bucket, [0, 0])
      result[:"#{bucket}_count"] = count
      result[:"#{bucket}_value_cents"] = value
    end
    finish(row)
  end

  def finish(row)
    issued = BUCKETS.excluding('canceled')
    row[:issued_count] = issued.sum { |bucket| row[:"#{bucket}_count"] }
    row[:issued_value_cents] = issued.sum { |bucket| row[:"#{bucket}_value_cents"] }
    row[:acceptance_rate] = rate(row[:accepted_count], row[:accepted_count] + row[:rejected_count] + row[:expired_count])
    row
  end

  def average_days(scope)
    days = scope.where(status: [:accepted, :rejected]).where.not(sent_at: nil).where.not(decided_at: nil)
                .pick(Arel.sql("AVG(EXTRACT(EPOCH FROM (#{TABLE}.decided_at - #{TABLE}.sent_at)) / 86400.0)"))
    days&.to_f&.round(1)
  end

  # Uma linha por responsável (nil = sem responsável), com nome e em ordem alfabética
  def owners
    grouped = @scope.group(:owner_id, bucket_sql).pluck(:owner_id, bucket_sql, COUNT_SQL, VALUE_SQL).group_by(&:first)
    names = User.where(id: grouped.keys.compact).pluck(:id, :name).to_h
    rows = grouped.map do |id, list|
      totals(list.map { |_id, bucket, count, value| [bucket, count, value] }).merge(id: id, name: names[id])
    end
    rows.sort_by { |row| [row[:name] ? 0 : 1, row[:name].to_s.downcase] }
  end

  # Máquinas e itens mais propostos (catálogo pelo produto; item livre pela descrição)
  def products
    items = Outsider::Crm::ProposalItem.joins(:proposal).merge(@scope.where.not(status: :canceled))
    rows = items.group(PRODUCT_KEY_SQL).order(Arel.sql('2 DESC')).limit(TOP_PRODUCTS).pluck(PRODUCT_KEY_SQL, *product_columns)
    names = Outsider::Crm::Product.where(id: rows.filter_map(&:last)).pluck(:id, :name).to_h
    rows.map { |row| product_row(row, names) }
  end

  def product_columns
    accepted = "#{TABLE}.status = #{Outsider::Crm::Proposal.statuses[:accepted]}"
    [
      'SUM(outsider_crm_proposal_items.quantity)', "COUNT(DISTINCT #{TABLE}.id)",
      "COALESCE(SUM(outsider_crm_proposal_items.quantity) FILTER (WHERE #{accepted}), 0)",
      "COALESCE(SUM(outsider_crm_proposal_items.total_cents) FILTER (WHERE #{accepted}), 0)",
      'MAX(outsider_crm_proposal_items.description)', 'MAX(outsider_crm_proposal_items.product_id)'
    ].map { |sql| Arel.sql(sql) }
  end

  def product_row(row, names)
    _key, quantity, proposals, accepted_quantity, accepted_value, description, product_id = row
    { product_id: product_id, name: names[product_id] || description, quantity: quantity.to_f, proposals_count: proposals,
      accepted_quantity: accepted_quantity.to_f, accepted_value_cents: accepted_value.to_i }
  end

  def rate(part, total)
    total.zero? ? nil : (part * 100.0 / total).round(1)
  end
end
