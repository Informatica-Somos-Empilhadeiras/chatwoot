# OUTSIDER: um agendamento de OS do ERP nas agendas de quem agendou (Outsider::Erp::OrderScheduler). O evento em si
# mora na agenda da Microsoft e/ou do Google da pessoa; aqui fica o resumo para o painel da OS e para cancelar.
# events: [{ 'provider' => 'microsoft'|'google', 'id', 'web_link' }]; attendees: e-mails convidados.
class Outsider::Erp::OrderSchedule < ApplicationRecord
  self.table_name = 'outsider_erp_order_schedules'

  belongs_to :account
  belongs_to :user, optional: true

  validates :company, presence: true, format: { with: Outsider::Erp::Sql::IDENT }
  validates :order_number, numericality: { only_integer: true, greater_than: 0 }
  validates :title, presence: true, length: { maximum: 250 }

  scope :for_order, ->(company, number) { where(company: company.to_s, order_number: number.to_i) }

  def providers = events.pluck('provider')
end
