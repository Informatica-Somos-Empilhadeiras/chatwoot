# OUTSIDER: põe o campo "Telas só para administradores" no formulário e na página de contas do Super Admin, depois do
# campo do CRM, sem mexer no app/dashboards/account_dashboard.rb. Prepend feito no config/initializers/outsider_access.rb.
module Outsider::Access::AccountDashboardField
  FIELD = :outsider_access_admin_only

  def attribute_types
    super.merge(FIELD => OutsiderAccessCeilingField)
  end

  def show_page_attributes
    with_field(super)
  end

  def form_attributes(action = nil)
    with_field(super)
  end

  private

  def with_field(attributes)
    return attributes if !attributes.is_a?(Array) || attributes.include?(FIELD)

    index = attributes.index(:outsider_crm_enabled) || attributes.index(:status)
    index ? attributes.dup.insert(index + 1, FIELD) : attributes + [FIELD]
  end
end
