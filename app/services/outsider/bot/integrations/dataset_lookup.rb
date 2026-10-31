# OUTSIDER: o bloco Planilha procura uma linha numa planilha do bot (Outsider::Bot::Dataset). A comparação
# ignora acento, maiúscula, espaço e pontuação: "CPCD-25" acha "cpcd 25" e o CNPJ vale com ou sem pontos.
#   equals       igual (usa o índice: milissegundos mesmo com 100 mil linhas)
#   contains     contém
#   starts_with  começa com
#   ends_with    termina com (telefone pelos últimos 8 dígitos, por exemplo)
class Outsider::Bot::Integrations::DatasetLookup
  OPERATORS = %w[equals contains starts_with ends_with].freeze

  def initialize(dataset)
    @dataset = dataset
  end

  # a primeira linha que serve (na ordem da planilha), como { 'coluna' => 'valor' }, ou nil
  def find(column:, operator:, value:)
    folded = Outsider::Bot::DatasetRow.fold(value)
    return if folded.blank? || @dataset.column_keys.exclude?(column)

    scope(column, OPERATORS.include?(operator) ? operator : 'equals', folded).order(:position).first&.data
  end

  private

  # folded só tem letras e números, então não sobra % nem _ para o LIKE
  def scope(column, operator, folded)
    rows = @dataset.rows
    case operator
    when 'contains' then rows.where('folded ->> ? LIKE ?', column, "%#{folded}%")
    when 'starts_with' then rows.where('folded ->> ? LIKE ?', column, "#{folded}%")
    when 'ends_with' then rows.where('folded ->> ? LIKE ?', column, "%#{folded}")
    else rows.where('folded @> ?', { column => folded }.to_json)
    end
  end
end
