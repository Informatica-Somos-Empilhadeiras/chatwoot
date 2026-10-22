# OUTSIDER: base dos controllers de propostas e catálogo. Quem tem o CRM entra; o que cada um vê e altera
# vem de Outsider::Crm::ProposalAccess. Os dois modelos padrão são criados na primeira visita.
class Api::V1::Accounts::Outsider::Crm::ProposalBaseController < Api::V1::Accounts::Outsider::Crm::BaseController
  before_action :ensure_templates

  rescue_from ::Outsider::Crm::ProposalSaver::Forbidden do
    render_forbidden
  end

  rescue_from ::Outsider::Crm::ImageShrinker::Invalid do
    render json: { error: 'invalid_image', message: I18n.t('outsider_crm.proposals.invalid_image') }, status: :unprocessable_entity
  end

  private

  def proposal_access
    @proposal_access ||= ::Outsider::Crm::ProposalAccess.new(Current.account_user)
  end

  def ensure_templates
    ::Outsider::Crm::ProposalTemplateDefaults.ensure!(Current.account)
  end

  def ensure_catalog_manager
    render_forbidden unless proposal_access.manage_catalog?
  end

  def image_upload
    params.require(:image).tap { |upload| raise ::Outsider::Crm::ImageShrinker::Invalid unless upload.respond_to?(:tempfile) }
  end
end
