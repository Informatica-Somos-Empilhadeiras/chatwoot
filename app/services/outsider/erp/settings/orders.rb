# OUTSIDER: o que a OS feita no chat usa das Configurações (Outsider::Erp::Orders::Creator): Nova OS e Converter
# orçamento em OS ligam separados (os dois começam desligados) e só valem nas unidades marcadas em order_companies
# (piloto: comece por uma). "Liberar para separação" (Outsider::Erp::Orders::Releaser) também começa desligado e vale
# nas mesmas unidades. Parte do Outsider::Erp::Settings.
module Outsider::Erp::Settings::Orders
  ORDERS_DEFAULTS = { 'order_create_enabled' => false, 'quote_convert_enabled' => false, 'order_release_enabled' => false,
                      'order_companies' => [] }.freeze

  def order_create_enabled? = enabled? && data['order_create_enabled'] == true
  def quote_convert_enabled? = enabled? && data['quote_convert_enabled'] == true
  def order_release_enabled? = enabled? && data['order_release_enabled'] == true
  def order_companies = Array(data['order_companies']).map(&:to_s) & companies
  def order_company?(company) = order_companies.include?(company.to_s)

  private

  # unidade que saiu da lista de unidades sai daqui também (vale a lista que está sendo salva agora)
  def clean_orders(params)
    units = Array(params.fetch('companies', companies)).map { |item| item.to_s.strip.downcase }
    list = Array(params.fetch('order_companies', data['order_companies'])).map { |item| item.to_s.strip.downcase }
    {
      'order_create_enabled' => flag(params, 'order_create_enabled'), 'quote_convert_enabled' => flag(params, 'quote_convert_enabled'),
      'order_release_enabled' => flag(params, 'order_release_enabled'), 'order_companies' => (list & units).uniq
    }
  end
end
