# OUTSIDER: listas de apoio do Kanban do ERP (situações, técnicos, tipos de atendimento) para os seletores da tela de
# edição da OS (ver Outsider::Erp::Lists). Só leitura e em cache; exige o acesso de uso da integração.
class Api::V1::Accounts::Outsider::Erp::ListsController < Api::V1::Accounts::Outsider::Erp::BaseController
  before_action :ensure_erp_use

  def index
    render json: { statuses: lists.statuses, technicians: lists.technicians, attendance_types: lists.attendance_types }
  end

  private

  def lists
    @lists ||= ::Outsider::Erp::Lists.new(Current.account)
  end

  def ensure_erp_use
    render json: { error: 'erp_forbidden' }, status: :forbidden unless can_use_erp?
  end
end
