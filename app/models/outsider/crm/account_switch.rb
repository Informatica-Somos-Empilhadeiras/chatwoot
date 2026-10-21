# OUTSIDER: o campo "CRM" da conta no Super Admin (ver Outsider::Crm::AccountDashboardSwitch). Lê e grava
# a chave da conta de Outsider::Crm::Switch dentro de accounts.internal_attributes, sem coluna nova.
# A gravação mexe só nessa chave, direto no banco (jsonb_set), para não sobrescrever o que o CRM gravou
# no mesmo campo enquanto o formulário estava aberto (rodízio, regras, agentes desligados).
# Incluído no Account pelo config/initializers/outsider_crm.rb.
module Outsider::Crm::AccountSwitch
  extend ActiveSupport::Concern

  included do
    after_save :outsider_crm_save_switch, unless: -> { @outsider_crm_enabled.nil? }
    after_commit :outsider_crm_switch_changed, if: -> { @outsider_crm_switch_changed }
  end

  def outsider_crm_enabled
    @outsider_crm_enabled.nil? ? Outsider::Crm::Switch.new(self).account_enabled? : @outsider_crm_enabled
  end

  def outsider_crm_enabled=(value)
    @outsider_crm_enabled = ActiveModel::Type::Boolean.new.cast(value) == true
  end

  private

  def outsider_crm_save_switch
    enabled = @outsider_crm_enabled
    @outsider_crm_enabled = nil
    key = Outsider::Crm::Switch::ACCOUNT_KEY
    stored = self.class.where(id: id).pick(Arel.sql("internal_attributes ->> '#{key}'")) == 'true'
    return if stored == enabled

    self.class.where(id: id).update_all( # rubocop:disable Rails/SkipsModelValidations
      ["internal_attributes = jsonb_set(COALESCE(internal_attributes, '{}'::jsonb), ?::text[], to_jsonb(?::boolean))", "{#{key}}", enabled]
    )
    self.internal_attributes = internal_attributes.to_h.merge(key => enabled)
    clear_attribute_changes([:internal_attributes])
    @outsider_crm_switch_changed = true
  end

  # telas do CRM abertas na conta conferem o acesso de novo
  def outsider_crm_switch_changed
    @outsider_crm_switch_changed = false
    Outsider::Crm::LiveUpdates.broadcast(id, 'access')
  end
end
