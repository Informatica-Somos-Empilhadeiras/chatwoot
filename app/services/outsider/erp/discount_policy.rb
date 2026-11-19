# OUTSIDER: limite de desconto do orçamento de peças e serviços (Outsider::Erp::Budget) sem liberação gerencial. O ERP da
# Somos não tem limite preenchido (empresa.DescontoMaximoForcaDeVendas = 0, produtos e clientes vazios), então o limite
# fica nas Configurações: desconto livre até X% em cada linha e Y% no total. Acima disso, quem tem a permissão de
# desconto do ERP libera com o código e a senha dele (Outsider::Erp::DiscountApprover).
#
# A liberação guarda o desconto liberado de cada produto e o total: baixar continua valendo; subir, ou pôr desconto num
# produto que não estava liberado, pede de novo.
class Outsider::Erp::DiscountPolicy
  def initialize(budget, settings)
    @budget = budget
    @settings = settings
  end

  # limites para a tela avisar na hora (o servidor confere de novo)
  def self.limits(settings)
    data = settings.data
    { enabled: data['quote_discount_approval'] == true, line_max: data['quote_discount_line_max'].to_f,
      total_max: data['quote_discount_total_max'].to_f }
  end

  def enabled? = @settings.data['quote_discount_approval'] == true
  def line_max = @settings.data['quote_discount_line_max'].to_d
  def total_max = @settings.data['quote_discount_total_max'].to_d

  # desconto do orçamento inteiro em % (descontos / valor cheio)
  def total_pct
    gross = @budget.items.sum { |item| item['quantidade'].to_d * item['preco'].to_d }
    return 0.to_d unless gross.positive?

    discounts = gross - @budget.total
    (discounts * 100 / gross).round(2)
  end

  def over_lines
    return [] unless enabled?

    discounted.select { |_code, percent| percent > line_max }.keys
  end

  def over_total? = enabled? && total_pct > total_max
  def needs_approval? = over_lines.any? || over_total?
  def blocked? = needs_approval? && !approved?

  def approved?
    approval = @budget.approval.to_h
    return false if approval['by_code'].blank?

    lines = approval['lines'].to_h
    discounted.all? { |code, percent| percent <= line_max || percent <= lines[code].to_d } &&
      (total_pct <= total_max || total_pct <= approval['total_pct'].to_d)
  end

  # o que a pessoa liberou vale para os descontos que estão na tela agora
  def grant(code:, name:, user:)
    @budget.update!(approval: {
                      'by_code' => code, 'by_name' => name.to_s.squish.first(80), 'user_id' => user&.id, 'at' => Time.current.iso8601,
                      'lines' => discounted.transform_values(&:to_f), 'total_pct' => total_pct.to_f
                    })
  end

  def as_json(*)
    approval = @budget.approval.to_h
    {
      enabled: enabled?, line_max: line_max.to_f, total_max: total_max.to_f, total_pct: total_pct.to_f, over_lines: over_lines,
      over_total: over_total?, needs_approval: needs_approval?, approved: needs_approval? && approved?,
      approved_by: approval['by_name'], approved_at: approval['at']
    }
  end

  private

  # código do produto (texto) => maior desconto em % dele no orçamento
  def discounted
    @budget.items.each_with_object({}) do |item, map|
      percent = item['desconto'].to_d
      next unless percent.positive?

      code = item['codigo'].to_s
      map[code] = [map[code].to_d, percent].max
    end
  end
end
