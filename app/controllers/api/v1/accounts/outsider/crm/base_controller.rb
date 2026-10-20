# OUTSIDER: base dos controllers do CRM. Sessão, conta e papel vêm do Chatwoot
# (Api::V1::Accounts::BaseController); aqui só barra quem não tem acesso ao CRM.
class Api::V1::Accounts::Outsider::Crm::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_crm_access

  rescue_from ActiveRecord::RecordInvalid do |error|
    render json: { error: 'invalid', message: error.record.errors.full_messages.to_sentence, errors: error.record.errors.details },
           status: :unprocessable_entity
  end

  # Apagar recusado: reason diz o que impede (ver Outsider::Crm::Remover) e a tela traduz
  rescue_from ::Outsider::Crm::Remover::Blocked do |error|
    render json: { error: 'in_use', reason: error.reason }.merge(error.details), status: :unprocessable_entity
  end

  private

  def crm_access
    @crm_access ||= ::Outsider::Crm::Access.new(Current.account_user)
  end

  def ensure_crm_access
    render json: { error: 'crm_access_denied' }, status: :forbidden unless crm_access.enabled?
  end

  def ensure_crm_admin
    render json: { error: 'crm_admin_only' }, status: :forbidden unless crm_access.administrator?
  end

  def render_forbidden
    render json: { error: 'crm_forbidden' }, status: :forbidden
  end

  def remover
    ::Outsider::Crm::Remover.new(Current.account)
  end

  def crm_scope(model)
    model.where(account_id: Current.account.id)
  end
end
