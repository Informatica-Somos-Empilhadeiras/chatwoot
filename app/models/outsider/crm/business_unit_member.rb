# OUTSIDER: agente que trabalha numa unidade. seller vê as oportunidades da unidade e edita as
# suas; manager edita todas da unidade (ver app/services/outsider/crm/access.rb).
class Outsider::Crm::BusinessUnitMember < ApplicationRecord
  include Outsider::Crm::AccountScoped

  audited associated_with: :account

  belongs_to :business_unit, class_name: 'Outsider::Crm::BusinessUnit'
  belongs_to :user

  enum role: { seller: 0, manager: 1 }

  validates :user_id, uniqueness: { scope: :business_unit_id }
  validates_same_account :business_unit
  validate :user_in_account

  private

  def user_in_account
    return if user.blank? || account.blank?

    errors.add(:user, :invalid) unless account.account_users.exists?(user_id: user_id)
  end
end
