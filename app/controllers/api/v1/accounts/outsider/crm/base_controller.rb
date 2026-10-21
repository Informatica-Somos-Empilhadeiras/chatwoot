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
    # reason: 'account' (CRM desligado na conta), 'agent' (desligado para a pessoa) ou 'no_unit'
    render json: { error: 'crm_access_denied', reason: crm_access.disabled_reason }, status: :forbidden unless crm_access.enabled?
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

  # Quem pode ter meta e comissão (Metas e Comissão): membros das unidades e administradores da conta
  def crm_people
    admins = Current.account.account_users.where(role: :administrator).pluck(:user_id)
    units = crm_scope(::Outsider::Crm::BusinessUnitMember).includes(:business_unit).group_by(&:user_id)
                                                          .transform_values { |list| list.map { |member| member.business_unit.name }.sort }
    User.where(id: (units.keys + admins).uniq).order(:name).map do |user|
      { id: user.id, name: user.name, thumbnail: user.avatar_url, units: units.fetch(user.id, []), administrator: admins.include?(user.id) }
    end
  end

  def crm_scope(model)
    model.where(account_id: Current.account.id)
  end
end
