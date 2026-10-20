require 'csv'

# OUTSIDER: exportação da tabela de negócios em CSV (separador ; para abrir direto no Excel em pt-BR).
class Outsider::Crm::OpportunitiesCsv
  LIMIT = 5000
  STATUS = { 'open' => 'aberto', 'won' => 'ganho', 'lost' => 'perdido', 'forwarded' => 'encaminhado' }.freeze
  HEADERS = %w[codigo negocio contato telefone unidade pipeline etapa valor probabilidade previsao responsavel status criado_em fechado_em].freeze

  def initialize(scope)
    @scope = scope.includes(:contact, :owner, :stage, :pipeline, :business_unit).limit(LIMIT)
  end

  def generate
    CSV.generate(col_sep: ';') do |csv|
      csv << HEADERS
      @scope.each { |opportunity| csv << row(opportunity) }
    end
  end

  private

  def row(opportunity)
    [
      opportunity.code, opportunity.title, opportunity.contact&.name, opportunity.contact&.phone_number,
      opportunity.business_unit.name, opportunity.pipeline.name, opportunity.stage.name,
      format('%.2f', opportunity.value).tr('.', ','), opportunity.effective_probability, opportunity.expected_close_on,
      opportunity.owner&.name, STATUS[opportunity.status], opportunity.created_at.to_date, opportunity.closed_at&.to_date
    ]
  end
end
