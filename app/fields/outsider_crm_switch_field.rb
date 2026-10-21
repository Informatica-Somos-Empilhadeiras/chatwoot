require 'administrate/field/boolean'

# OUTSIDER: campo "CRM" da conta no Super Admin (Outsider::Crm::AccountDashboardSwitch)
class OutsiderCrmSwitchField < Administrate::Field::Boolean
  def to_s
    I18n.t(data ? 'outsider_crm.switch.enabled' : 'outsider_crm.switch.disabled')
  end
end
