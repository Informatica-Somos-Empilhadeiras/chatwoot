# OUTSIDER: o perfil de acesso de uma pessoa na conta. Sem linha, a pessoa usa o perfil padrão do tipo dela (Agente).
# == Schema Information
#
# Table name: outsider_access_members
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  profile_id :bigint           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_outsider_access_members_on_account_id_and_user_id  (account_id,user_id) UNIQUE
#  index_outsider_access_members_on_profile_id              (profile_id)
#
class Outsider::AccessMember < ApplicationRecord
  self.table_name = 'outsider_access_members'

  belongs_to :account
  belongs_to :user
  belongs_to :profile, class_name: 'Outsider::AccessProfile', inverse_of: :members

  validates :user_id, uniqueness: { scope: :account_id }
  validate :same_account

  private

  def same_account
    errors.add(:profile, :invalid) if profile && profile.account_id != account_id
  end
end
