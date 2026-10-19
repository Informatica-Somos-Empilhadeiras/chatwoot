# OUTSIDER: jornada comercial de um lead: agrupa as oportunidades do mesmo contato nas várias
# unidades, inclusive as encaminhadas, sem apagar as anteriores.
class Outsider::Crm::Journey < ApplicationRecord
  include Outsider::Crm::AccountScoped

  belongs_to :contact
  belongs_to :company, optional: true
  has_many :opportunities, class_name: 'Outsider::Crm::Opportunity', dependent: :restrict_with_error
  has_many :forwards, class_name: 'Outsider::Crm::Forward', dependent: :restrict_with_error

  enum status: { open: 0, won: 1, closed: 2 }

  validates_same_account :contact, :company
end
