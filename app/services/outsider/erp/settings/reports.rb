# OUTSIDER: o que o relatório de desempenho dos técnicos (Outsider::Erp::TechnicianReport) usa das Configurações: o %
# de comissão sobre o valor faturado (a planilha usava 1%), a meta do mês de cada técnico, pelo nome, e os tipos de
# atendimento da OS que não entram na soma do técnico (garantia, entrega técnica e frotas não geram valor para ele).
# Parte do Outsider::Erp::Settings.
module Outsider::Erp::Settings::Reports
  REPORTS_DEFAULTS = {
    'report_commission_pct' => 1.0, 'report_goals' => {}, 'report_excluded_types' => ['GARANTIA', 'ENTREGA TÉCNICA', 'FROTAS']
  }.freeze
  MAX_GOALS = 100
  MAX_EXCLUDED = 30

  def report_commission_pct = data['report_commission_pct'].to_f
  def report_goals = data['report_goals'].to_h
  def report_excluded_types = Array(data['report_excluded_types']).map(&:to_s)

  # o tipo da OS fica fora da soma? Sem acento nem maiúsculas, e por pedaço: "FROTAS" pega "FROTA" e "MANUT. FROTA"
  def report_excluded?(type)
    name = normalize_report_type(type)
    return false if name.blank?

    report_excluded_types.any? do |entry|
      stem = normalize_report_type(entry)
      stem = stem.delete_suffix('S') if stem.size > 4
      stem.present? && name.include?(stem)
    end
  end

  private

  def normalize_report_type(value) = Outsider::Erp::Prints::Bindings.normalize_type(value)

  def clean_reports(params)
    pct = params.fetch('report_commission_pct', report_commission_pct).to_s.tr(',', '.').to_f
    @errors << 'report_commission_pct' unless pct.between?(0, 100)
    {
      'report_commission_pct' => pct.clamp(0, 100).round(2), 'report_goals' => clean_goals(params.fetch('report_goals', report_goals)),
      'report_excluded_types' => clean_excluded(params.fetch('report_excluded_types', report_excluded_types))
    }
  end

  # { "NOME DO TÉCNICO" => meta em R$ }; meta vazia ou zero tira o técnico
  def clean_goals(goals)
    return report_goals unless goals.is_a?(Hash)

    goals.to_h { |name, value| [name.to_s.squish.upcase.first(80), value.to_s.tr(',', '.').to_f.round(2)] }
         .select { |name, value| name.present? && value.positive? }.first(MAX_GOALS).to_h
  end

  # como a pessoa escreveu, em maiúsculas (a comparação ignora acento); repetido sem acento sai
  def clean_excluded(types)
    return report_excluded_types unless types.is_a?(Array)

    types.map { |type| type.to_s.squish.upcase.first(80) }.compact_blank.uniq { |type| normalize_report_type(type) }.first(MAX_EXCLUDED)
  end
end
