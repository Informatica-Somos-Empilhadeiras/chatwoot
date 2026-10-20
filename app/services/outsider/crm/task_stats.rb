# OUTSIDER: tarefas pendentes de cada oportunidade (quantas, quantas atrasadas e o próximo prazo),
# numa consulta só para a lista inteira de negócios (Kanban, tabela, aba da conversa).
module Outsider::Crm::TaskStats
  EMPTY = { pending: 0, overdue: 0, next_due_at: nil }.freeze

  module_function

  def for(opportunity_ids)
    overdue = Outsider::Crm::Task.sanitize_sql_array(['COUNT(*) FILTER (WHERE due_at < ?)', Time.current])
    rows = Outsider::Crm::Task.pending.where(opportunity_id: opportunity_ids).group(:opportunity_id)
                              .pluck(:opportunity_id, Arel.sql('COUNT(*)'), Arel.sql(overdue), Arel.sql('MIN(due_at)'))
    stats = rows.to_h { |id, pending, late, next_due_at| [id, { pending: pending, overdue: late, next_due_at: next_due_at }] }
    stats.default = EMPTY
    stats
  end
end
