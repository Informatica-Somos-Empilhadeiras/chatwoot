# OUTSIDER: Configurações > Propostas (só administrador): próximo número, dados da empresa (padrão e por
# unidade), quem vê as propostas de quem, quem mexe no catálogo e a assinatura de cada pessoa.
class Api::V1::Accounts::Outsider::Crm::ProposalSettingsController < Api::V1::Accounts::Outsider::Crm::ProposalBaseController
  before_action :ensure_crm_admin

  rescue_from ::Outsider::Crm::ProposalConfig::Invalid do |error|
    render json: { error: 'invalid', message: error.message }, status: :unprocessable_entity
  end

  def show
    render json: payload
  end

  def general
    proposal_config.update_general(next_number: params.require(:next_number))
    render json: payload
  end

  def company
    proposal_config.update_company(params.require(:company).permit(*::Outsider::Crm::ProposalConfig::COMPANY_KEYS), unit_id: params[:unit_id])
    render json: payload
  end

  def access
    user_id = params[:user_id].to_i
    return head :not_found unless Current.account.account_users.exists?(user_id: user_id)

    proposal_config.update_access(user_id, params.require(:access).permit(:view, :catalog, user_ids: []))
    render json: payload
  end

  def signature
    user_id = params[:user_id].to_i
    return head :not_found unless Current.account.account_users.exists?(user_id: user_id)

    proposal_config.update_signature(user_id, params.require(:signature).permit(*::Outsider::Crm::ProposalConfig::SIGNATURE_KEYS))
    render json: payload
  end

  private

  def proposal_config
    @proposal_config ||= ::Outsider::Crm::ProposalConfig.new(Current.account)
  end

  def payload
    settings = ::Outsider::Crm::ProposalConfig.new(Current.account.reload)
    {
      next_number: settings.next_number,
      last_number: crm_scope(::Outsider::Crm::Proposal).maximum(:number),
      company: settings.company,
      unit_companies: settings.unit_companies,
      people: people(settings)
    }
  end

  # Todos da conta (administradores sempre veem tudo), com a regra de visibilidade e a assinatura
  def people(settings)
    Current.account.account_users.includes(:user).sort_by { |account_user| account_user.user.name.to_s.downcase }.map do |account_user|
      user = account_user.user
      { id: user.id, name: user.name, email: user.email, thumbnail: user.avatar_url, administrator: account_user.administrator?,
        access: settings.access(user.id), signature: settings.signature(user.id) }
    end
  end
end
