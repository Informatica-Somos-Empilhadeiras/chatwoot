require 'administrate/field/base'

# OUTSIDER: campo "Telas só para administradores" da conta no Super Admin (Outsider::Access::AccountDashboardField)
class OutsiderAccessCeilingField < Administrate::Field::Base
  def self.permitted_attribute(attribute, _options = {})
    { attribute => [] }
  end

  def screens
    Outsider::Access::Catalog::SCREENS.reject { |screen| screen[:admin_only] }.pluck(:key)
  end

  def selected
    Array(data)
  end

  def label(screen)
    I18n.t("outsider_access.screens.#{screen}")
  end

  def to_s
    selected.empty? ? I18n.t('outsider_access.ceiling.none') : selected.map { |screen| label(screen) }.join(', ')
  end
end
