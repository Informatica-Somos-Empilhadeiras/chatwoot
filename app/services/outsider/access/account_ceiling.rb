# OUTSIDER: o campo "Telas só para administradores" da conta no Super Admin (Outsider::Access::AccountDashboardField).
# Guarda a lista em accounts.internal_attributes (outsider_access_admin_only), mexendo só nessa chave (jsonb_set), como o
# campo do CRM. Incluído no Account pelo config/initializers/outsider_access.rb.
module Outsider::Access::AccountCeiling
  extend ActiveSupport::Concern

  included do
    after_save :outsider_access_save_ceiling, unless: -> { @outsider_access_admin_only.nil? }
  end

  def outsider_access_admin_only
    @outsider_access_admin_only || Array(internal_attributes.to_h[Outsider::Access::ADMIN_ONLY_KEY])
  end

  def outsider_access_admin_only=(value)
    @outsider_access_admin_only = Array(value).map(&:to_s) & Outsider::Access::Catalog::KEYS
  end

  private

  def outsider_access_save_ceiling
    screens = @outsider_access_admin_only
    @outsider_access_admin_only = nil
    key = Outsider::Access::ADMIN_ONLY_KEY
    self.class.where(id: id).update_all( # rubocop:disable Rails/SkipsModelValidations
      ["internal_attributes = jsonb_set(COALESCE(internal_attributes, '{}'::jsonb), ?::text[], ?::jsonb)", "{#{key}}", screens.to_json]
    )
    self.internal_attributes = internal_attributes.to_h.merge(key => screens)
    clear_attribute_changes([:internal_attributes])
  end
end
