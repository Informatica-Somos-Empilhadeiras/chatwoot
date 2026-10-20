# OUTSIDER: jornada comercial de um lead: agrupa as oportunidades do mesmo contato nas várias
# unidades, inclusive as encaminhadas, sem apagar as anteriores. O limite de encaminhamentos
# (Settings max_forward_attempts) conta os encaminhamentos da jornada.
class Outsider::Crm::Journey < ApplicationRecord
  include Outsider::Crm::AccountScoped

  belongs_to :contact
  belongs_to :company, optional: true
  has_many :opportunities, class_name: 'Outsider::Crm::Opportunity', dependent: :restrict_with_error
  has_many :forwards, class_name: 'Outsider::Crm::Forward', dependent: :restrict_with_error

  enum :status, { open: 0, won: 1, closed: 2 }, validate: true

  validates_same_account :contact, :company

  # A jornada fica em andamento enquanto houver oportunidade aberta. Quando todas encerram, fecha
  # como ganha se alguma foi ganha, senão como encerrada; reabrir uma oportunidade reabre a jornada.
  def sync_status!
    new_status = status_from(opportunities.distinct.pluck(:status))
    return if status == new_status

    update!(status: new_status, closed_at: new_status == 'open' ? nil : Time.current)
  end

  private

  def status_from(statuses)
    return 'open' if statuses.include?('open') || statuses.empty?
    return 'won' if statuses.include?('won')

    'closed'
  end
end
