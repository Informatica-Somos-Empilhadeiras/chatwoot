# OUTSIDER: modelos de proposta. Todos do CRM listam (para escolher na proposta); o administrador altera os
# textos padrão e troca o cabeçalho e o rodapé (papel timbrado). O editor de posição fica para depois.
class Api::V1::Accounts::Outsider::Crm::ProposalTemplatesController < Api::V1::Accounts::Outsider::Crm::ProposalBaseController
  SLOTS = { 'header' => :header_image, 'footer' => :footer_image }.freeze
  IMAGE_MAX_SIZE = 2000

  before_action :ensure_crm_admin, except: [:index, :show]
  before_action :fetch_template, except: [:index]

  def index
    templates = crm_scope(::Outsider::Crm::ProposalTemplate).with_attached_header_image.with_attached_footer_image.ordered
    render json: templates.map { |template| serializer.template(template) }
  end

  def show
    render json: serializer.template(@template)
  end

  def update
    values = template_params.to_h
    values[:content] = @template.content.merge(values[:content].to_h) if values.key?(:content)
    @template.update!(values)
    render json: serializer.template(@template)
  end

  def upload_image
    slot = SLOTS.fetch(params[:slot]) { return head(:not_found) }
    @template.public_send(slot).attach(::Outsider::Crm::ImageShrinker.new(image_upload, max_size: IMAGE_MAX_SIZE).attachable)
    @template.save!
    render json: serializer.template(@template.reload)
  end

  # Sem imagem própria, o modelo padrão volta ao papel timbrado que vem com o CRM
  def remove_image
    slot = SLOTS.fetch(params[:slot]) { return head(:not_found) }
    attachment = @template.public_send(slot)
    attachment.purge_later if attachment.attached?
    render json: serializer.template(@template.reload)
  end

  private

  def serializer
    ::Outsider::Crm::ProposalSerializer
  end

  def fetch_template
    @template = crm_scope(::Outsider::Crm::ProposalTemplate).find(params[:id])
  end

  def template_params
    params.require(:proposal_template).permit(
      :name, :active,
      content: [*::Outsider::Crm::ProposalTemplate::TEXT_KEYS, *::Outsider::Crm::ProposalTemplate::FLAG_KEYS, :validity_days,
                :conditions_style, { conditions: [:label, :text] }]
    )
  end
end
