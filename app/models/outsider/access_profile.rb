# OUTSIDER: perfil de acesso por tela (Configurações > Perfis de acesso). Os três prontos (Administrador, Agente e
# Técnico) nascem sozinhos na conta (Outsider::Access::Defaults); o administrador cria outros e escolhe, tela por tela,
# Não vê, Vê, Usa ou Gerencia. O perfil só tira o que o papel do Chatwoot dá (nunca transforma agente em administrador);
# Gerencia só existe nas telas que têm algo a mais para gerenciar (Outsider::Access::Catalog).
# == Schema Information
#
# Table name: outsider_access_profiles
#
#  id            :bigint           not null, primary key
#  default_for   :string
#  description   :string
#  kind          :string           default("custom"), not null
#  name          :string           not null
#  permissions   :jsonb            not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  created_by_id :bigint
#
# Indexes
#
#  index_outsider_access_profiles_on_account_id           (account_id)
#  index_outsider_access_profiles_on_account_id_and_name  (account_id,name) UNIQUE
#
class Outsider::AccessProfile < ApplicationRecord
  self.table_name = 'outsider_access_profiles'

  KINDS = %w[administrator agent technician custom].freeze
  DEFAULT_FOR = %w[agent technician].freeze
  MAX_PER_ACCOUNT = 30

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  has_many :members, class_name: 'Outsider::AccessMember', foreign_key: :profile_id, inverse_of: :profile, dependent: :destroy

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: { scope: :account_id, case_sensitive: false }
  validates :description, length: { maximum: 160 }
  validates :kind, inclusion: { in: KINDS }
  validates :default_for, inclusion: { in: DEFAULT_FOR }, allow_nil: true
  validate :permissions_known

  scope :ordered, -> { order(Arel.sql("CASE kind WHEN 'administrator' THEN 0 WHEN 'agent' THEN 1 WHEN 'technician' THEN 2 ELSE 3 END"), :name) }

  def system? = kind != 'custom'
  def administrator? = kind == 'administrator'

  # tipo de usuário que este perfil serve: técnico (só telefone) ou agente
  def technician? = kind == 'technician' || (kind == 'custom' && permissions['conversations'] == 'none' && permissions['phone'] == 'use')

  def level(screen)
    Outsider::Access::Catalog.clamp(screen, permissions[screen.to_s] || Outsider::Access::Catalog.default_level(kind, screen))
  end

  private

  def permissions_known
    return errors.add(:permissions, :invalid) unless permissions.is_a?(Hash)

    permissions.each do |screen, value|
      errors.add(:permissions, :invalid) unless Outsider::Access::Catalog.levels(screen).include?(value)
    end
  end
end
