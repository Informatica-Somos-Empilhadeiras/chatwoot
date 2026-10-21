# OUTSIDER: põe o campo "CRM" (liga e desliga o CRM na conta) na lista, na página e no formulário de
# contas do Super Admin, logo depois de Status, sem mexer no app/dashboards/account_dashboard.rb.
# Prepend feito no config/initializers/outsider_crm.rb.
module Outsider::Crm::AccountDashboardSwitch
  FIELD = :outsider_crm_enabled

  def attribute_types
    super.merge(FIELD => OutsiderCrmSwitchField)
  end

  def collection_attributes
    with_switch(super)
  end

  def show_page_attributes
    with_switch(super)
  end

  def form_attributes(action = nil)
    with_switch(super)
  end

  private

  def with_switch(attributes)
    return attributes if !attributes.is_a?(Array) || attributes.include?(FIELD)

    index = attributes.index(:status)
    index ? attributes.dup.insert(index + 1, FIELD) : attributes + [FIELD]
  end
end
