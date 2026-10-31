# OUTSIDER: o bloco Decisão segue pela primeira regra que servir para o valor (um texto com {{variáveis}},
# como {{pedido.status}}); nenhuma servindo, segue por "nenhuma". Texto sem diferença de acento nem de
# maiúscula; maior e menor comparam números escritos do jeito brasileiro ou não ("1.234,56").
class Outsider::Bot::Integrations::Decision
  OPERATORS = %w[equals not_equals contains not_contains starts_with ends_with greater less empty not_empty].freeze
  EMPTY = ['', '[]', '{}', 'null', 'nil'].freeze

  def initialize(template)
    @template = template
  end

  def port(data)
    subject = @template.render(data['subject'])
    rule = Array(data['rules']).find { |item| match?(subject, item['operator'], @template.render(item['value'])) }
    rule ? rule['id'] : 'default'
  end

  # rubocop:disable Metrics/CyclomaticComplexity
  def match?(subject, operator, value)
    left = fold(subject)
    right = fold(value)
    case operator
    when 'equals' then left == right
    when 'not_equals' then left != right
    when 'contains' then right.present? && left.include?(right)
    when 'not_contains' then right.blank? || left.exclude?(right)
    when 'starts_with' then right.present? && left.start_with?(right)
    when 'ends_with' then right.present? && left.end_with?(right)
    when 'greater', 'less' then compare(subject, value, operator)
    when 'empty' then EMPTY.include?(left)
    when 'not_empty' then EMPTY.exclude?(left)
    else false
    end
  end
  # rubocop:enable Metrics/CyclomaticComplexity

  private

  def fold(text)
    ActiveSupport::Inflector.transliterate(text.to_s, '?').downcase.squish
  end

  def compare(subject, value, operator)
    left = Outsider::Bot::Template.number(subject)
    right = Outsider::Bot::Template.number(value)
    return false unless left && right

    operator == 'greater' ? left > right : left < right
  end
end
