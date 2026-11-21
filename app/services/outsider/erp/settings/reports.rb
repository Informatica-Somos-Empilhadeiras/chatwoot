# OUTSIDER: o que o relatório de desempenho dos técnicos (Outsider::Erp::TechnicianReport) usa das Configurações: o %
# de comissão sobre o valor faturado (a planilha usava 1%) e a meta do mês de cada técnico, pelo nome. Parte do
# Outsider::Erp::Settings.
module Outsider::Erp::Settings::Reports
  REPORTS_DEFAULTS = { 'report_commission_pct' => 1.0, 'report_goals' => {} }.freeze
  MAX_GOALS = 100

  def report_commission_pct = data['report_commission_pct'].to_f
  def report_goals = data['report_goals'].to_h

  private

  def clean_reports(params)
    pct = params.fetch('report_commission_pct', report_commission_pct).to_s.tr(',', '.').to_f
    @errors << 'report_commission_pct' unless pct.between?(0, 100)
    { 'report_commission_pct' => pct.clamp(0, 100).round(2), 'report_goals' => clean_goals(params.fetch('report_goals', report_goals)) }
  end

  # { "NOME DO TÉCNICO" => meta em R$ }; meta vazia ou zero tira o técnico
  def clean_goals(goals)
    return report_goals unless goals.is_a?(Hash)

    goals.to_h { |name, value| [name.to_s.squish.upcase.first(80), value.to_s.tr(',', '.').to_f.round(2)] }
         .select { |name, value| name.present? && value.positive? }.first(MAX_GOALS).to_h
  end
end
