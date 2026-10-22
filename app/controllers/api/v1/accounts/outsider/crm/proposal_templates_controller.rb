# OUTSIDER: modelos de proposta. Todos do CRM listam (para escolher na proposta); o administrador cria (em
# branco ou copiando outro modelo), altera textos, blocos e papel timbrado, troca as imagens, vê a prévia do
# PDF antes de salvar e apaga modelo que nenhuma proposta usa. Cada tipo (venda, locação) mantém pelo menos
# um modelo ativo, porque a proposta nova precisa de um.
class Api::V1::Accounts::Outsider::Crm::ProposalTemplatesController < Api::V1::Accounts::Outsider::Crm::ProposalBaseController
  SLOTS = { 'header' => :header_image, 'footer' => :footer_image }.freeze
  IMAGE_MAX_SIZE = 2000
  BLOCK_KEYS = %i[key type visible new_page size bold highlight image_side heading text equipment equipment_heading].freeze
  ELEMENT_KEYS = %i[id type x y width pages text size bold highlight color align image_id].freeze

  before_action :ensure_crm_admin, except: [:index, :show]
  before_action :fetch_template, except: [:index, :create, :default_image]

  def index
    templates = crm_scope(::Outsider::Crm::ProposalTemplate).with_attached_header_image.with_attached_footer_image.ordered
    render json: templates.map { |template| serializer.template(template) }
  end

  def show
    render json: serializer.template(@template)
  end

  # cópia fica com o tipo do original
  def create
    source = source_template
    template = ::Outsider::Crm::ProposalTemplateCopier.new(Current.account).create(
      name: params.require(:name), kind: source&.kind || params.require(:kind), source: source
    )
    render json: serializer.template(template), status: :created
  end

  def update
    assign_values
    return last_active_error unless keeps_active_template?

    @template.save!
    @template.unused_layout_images.each(&:purge_later)
    render json: serializer.template(@template.reload)
  end

  # PDF de uma proposta de exemplo com o que está na tela, sem salvar nada
  def preview
    assign_values
    return render json: { error: 'invalid', message: @template.errors.full_messages.to_sentence }, status: :unprocessable_entity if @template.invalid?

    proposal = ::Outsider::Crm::ProposalSample.new(Current.account_user, @template).build
    send_data ::Outsider::Crm::ProposalPdf.new(proposal, template: @template).render, type: 'application/pdf', disposition: 'inline'
  end

  def destroy
    if @template.proposals.exists?
      return render json: { error: 'in_use', message: I18n.t('outsider_crm.proposal_templates.in_use', count: @template.proposals.count) },
                    status: :unprocessable_entity
    end
    @template.active = false
    return last_active_error unless keeps_active_template?

    @template.destroy!
    head :no_content
  end

  def upload_image
    slot = SLOTS.fetch(params[:slot]) { return head(:not_found) }
    @template.public_send(slot).attach(shrunk_image)
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

  # Imagem de um elemento em posição livre; o elemento passa a usar o id devolvido quando o modelo é salvo
  def upload_layout_image
    if @template.layout_images.attachments.size >= ::Outsider::Crm::ProposalTemplateLayout::MAX_ELEMENTS * 2
      return render json: { error: 'too_many_images', message: I18n.t('outsider_crm.proposal_templates.too_many_images') },
                    status: :unprocessable_entity
    end

    @template.layout_images.attach(shrunk_image)
    attachment = @template.layout_images.attachments.max_by(&:id)
    render json: { id: attachment.id, url: serializer.file_path(attachment) }, status: :created
  end

  # Cabeçalho ou rodapé que vem com o CRM, para o desenho do papel timbrado no editor
  def default_image
    path = { 'header' => ::Outsider::Crm::ProposalPdf::DEFAULT_HEADER, 'footer' => ::Outsider::Crm::ProposalPdf::DEFAULT_FOOTER }[params[:slot]]
    return head(:not_found) unless path && File.exist?(path)

    send_file path, type: 'image/jpeg', disposition: 'inline'
  end

  private

  def serializer
    ::Outsider::Crm::ProposalSerializer
  end

  def fetch_template
    @template = crm_scope(::Outsider::Crm::ProposalTemplate).find(params[:id])
  end

  def source_template
    crm_scope(::Outsider::Crm::ProposalTemplate).find(params[:source_id]) if params[:source_id].present?
  end

  def shrunk_image
    ::Outsider::Crm::ImageShrinker.new(image_upload, max_size: IMAGE_MAX_SIZE).attachable
  end

  def assign_values
    values = template_params.to_h
    values[:content] = @template.content.merge(values[:content].to_h) if values.key?(:content)
    @template.assign_attributes(values)
  end

  def keeps_active_template?
    return true if @template.active?

    crm_scope(::Outsider::Crm::ProposalTemplate).active.where(kind: @template.kind).where.not(id: @template.id).exists?
  end

  def last_active_error
    render json: { error: 'last_active', message: I18n.t('outsider_crm.proposal_templates.last_active') }, status: :unprocessable_entity
  end

  def template_params
    params.require(:proposal_template).permit(
      :name, :active,
      content: [*::Outsider::Crm::ProposalTemplate::TEXT_KEYS, *::Outsider::Crm::ProposalTemplate::FLAG_KEYS, :validity_days,
                :conditions_style, { conditions: [:label, :text], blocks: BLOCK_KEYS,
                                     layout: [:font, :header_pages, :footer_pages, { margins: [:side, :top, :bottom], elements: ELEMENT_KEYS }] }]
    )
  end
end
