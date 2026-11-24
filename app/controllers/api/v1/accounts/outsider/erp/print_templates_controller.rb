# OUTSIDER: aba "Modelos de relatório" da seção ERP (só administradores): os modelos de impressão da OS e do orçamento
# (Outsider::Erp::PrintTemplate), o estúdio que monta cada um (blocos, campos, identidade visual) e qual modelo cada tipo
# de atendimento usa (Outsider::Erp::Prints::Bindings). A pré-visualização usa os dados de exemplo ou uma OS/orçamento de
# verdade, lido do ERP só para leitura (as mesmas rotas do relatório da OS e do PDF do orçamento).
class Api::V1::Accounts::Outsider::Erp::PrintTemplatesController < Api::V1::Accounts::Outsider::Erp::BaseController
  IMAGE_MAX_SIZE = 1600
  MAX_IMAGES = 30

  before_action :ensure_erp_admin
  before_action :fetch_template, only: %i[show update destroy restore preview upload_image]

  rescue_from(::Outsider::Erp::ServiceOrderReport::NotFound) { render json: { error: 'os_not_found' }, status: :not_found }
  rescue_from(::Outsider::Erp::QuoteReport::NotFound) { render json: { error: 'quote_not_found' }, status: :not_found }
  rescue_from(::Outsider::Crm::ImageShrinker::Invalid) { render json: { error: 'invalid_image' }, status: :unprocessable_entity }

  # a lista (os padrões entram na primeira vez), as escolhas por tipo de atendimento e o "cardápio" de cada tipo
  def index
    ::Outsider::Erp::PrintTemplate::KINDS.each { |kind| defaults.ensure!(Current.account, kind, user: Current.user) }
    render json: {
      templates: scope.with_attached_images.ordered.map { |template| summary(template) },
      bindings: bindings.to_h, attendance_types: attendance_types,
      catalog: ::Outsider::Erp::PrintTemplate::KINDS.index_with { |kind| ::Outsider::Erp::Prints::Catalog.to_h(kind) },
      builtins: defaults::TEMPLATES.transform_values { |data| data.slice('kind', 'name') }
    }
  end

  def show
    render json: { template: full(@template) }
  end

  # novo modelo: cópia de outro (source_id) ou o primeiro padrão do tipo, para não começar com a folha em branco
  def create
    source = scope.find(params[:source_id]) if params[:source_id].present?
    template = scope.create!(kind: source&.kind || kind_param, name: params[:name].presence || copy_name(source),
                             created_by_id: Current.user.id, content: source&.content || starter_content(kind_param))
    copy_images(source, template) if source
    render json: { template: full(template.reload) }, status: :created
  end

  def update
    @template.name = params[:name].to_s.strip if params.key?(:name)
    @template.content = content_param if params.key?(:content)
    @template.save!
    @template.unused_images.each(&:purge_later)
    render json: { template: full(@template.reload) }
  end

  def destroy
    @template.destroy!
    render json: { bindings: bindings.to_h }
  end

  def restore
    return render json: { error: 'not_builtin' }, status: :unprocessable_entity unless defaults.restore(@template)

    render json: { template: full(@template.reload) }
  end

  # imagem do modelo (logo próprio, imagem solta): o bloco passa a usar o id devolvido quando o modelo é salvo
  def upload_image
    return render json: { error: 'too_many_images' }, status: :unprocessable_entity if @template.images.attachments.size >= MAX_IMAGES

    @template.images.attach(::Outsider::Crm::ImageShrinker.new(params.require(:image), max_size: IMAGE_MAX_SIZE).attachable)
    attachment = @template.images.attachments.max_by(&:id)
    render json: { id: attachment.id, url: file_path(attachment) }, status: :created
  end

  # PDF do modelo como está na tela (sem salvar), com os dados de exemplo ou de uma OS / orçamento de verdade
  def preview
    @template.content = ::Outsider::Erp::Prints::Content.normalize(@template.kind, content_param) if params.key?(:content)
    document = preview_document
    send_data document.render, filename: document.filename, type: 'application/pdf', disposition: 'inline'
  end

  # os dados que a folha do estúdio desenha (formato do Outsider::Erp::Prints::Values): exemplo ou uma OS/orçamento real
  def sample
    kind = kind_param
    values = ::Outsider::Erp::Prints::Document.values(Current.account, kind, real? ? real_report(kind, photos: false) : sample_report(kind))
    emitter = values['emitter'].to_h
    logo = emitter['logo']
    render json: { values: values.merge('emitter' => emitter.except('logo').merge('logo_url' => data_uri(logo))) }
  end

  # foto do checklist de uma OS de verdade para a folha do estúdio: só "<OS>_<n>" daquela OS (como no relatório da OS)
  def photo
    company, code = real_target
    ref = params[:ref].to_s
    return head(:not_found) unless ref.match?(::Outsider::Erp::ServiceOrderReport::PHOTO_REF) && ref.start_with?("#{code}_")

    bytes = ::Outsider::Erp::Client.new(settings).checklist_photo(company, ref)
    return head(:not_found) unless bytes.start_with?("\xFF\xD8".b, "\x89PNG".b)

    expires_in 1.hour, public: false
    send_data bytes, type: bytes.start_with?("\x89PNG".b) ? 'image/png' : 'image/jpeg', disposition: 'inline'
  end

  # qual modelo cada tipo de atendimento usa (OS) e o padrão de cada tipo
  def bindings_update
    render json: { bindings: bindings.update(kind_param, default: params[:default], types: params[:types]&.to_unsafe_h) }
  end

  private

  def scope = ::Outsider::Erp::PrintTemplate.where(account_id: Current.account.id)
  def defaults = ::Outsider::Erp::Prints::Defaults
  def bindings = @bindings ||= ::Outsider::Erp::Prints::Bindings.new(Current.account)

  def fetch_template
    @template = scope.find(params[:id])
  end

  def kind_param
    kind = params.require(:kind).to_s
    raise ActionController::BadRequest, 'kind' unless ::Outsider::Erp::PrintTemplate::KINDS.include?(kind)

    kind
  end

  def content_param
    raw = params.require(:content)
    raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
  end

  # os tipos de atendimento do ERP (lista do kanban) mais os que já têm escolha (tipo que saiu da lista continua visível)
  def attendance_types
    listed = begin
      ::Outsider::Erp::Lists.new(Current.account).attendance_types
    rescue ::Outsider::Erp::Client::Error
      []
    end
    (listed.map { |type| ::Outsider::Erp::Prints::Bindings.normalize_type(type) } + bindings.to_h.dig('os', 'types').to_h.keys).uniq.sort
  end

  def starter_content(kind)
    key = defaults::TEMPLATES.find { |_, data| data['kind'] == kind }&.first
    raise ActionController::BadRequest, 'kind' unless key

    defaults.content(key)
  end

  def copy_name(source)
    source ? "#{source.name} (cópia)".first(120) : 'Novo modelo'
  end

  # a cópia leva as próprias imagens: os blocos passam a apontar para os anexos novos
  def copy_images(source, template)
    mapping = source.images.attachments.to_h { |attachment| [attachment.id, copy_image(template, attachment)] }
    return if mapping.empty?

    blocks = template.content['blocks'].map { |block| block.merge('image_id' => mapping.fetch(block['image_id'], block['image_id'])) }
    template.update!(content: template.content.merge('blocks' => blocks))
  end

  def copy_image(template, attachment)
    template.images.attach(attachment.blob)
    template.images.attachments.max_by(&:id).id
  end

  def real? = params[:company].present? && params[:number].present?

  def real_target
    company = params.require(:company).to_s
    code = Integer((params[:number] || params[:code]).to_s, exception: false)
    raise ::Outsider::Erp::ServiceOrderReport::NotFound unless code && settings.companies.include?(company)

    [company, code]
  end

  def real_report(kind, photos:)
    company, code = real_target
    return ::Outsider::Erp::QuoteReport.new(Current.account).build(company, code) if kind == 'quote'

    report = ::Outsider::Erp::ServiceOrderReport.new(Current.account).build(company, code, photos: photos)
    report.merge('emitente' => ::Outsider::Erp::Prints::Document.full_emitter(Current.account, company, report['emitente']))
  end

  def sample_report(kind) = ::Outsider::Erp::Prints::Sample.for(kind)

  def preview_document
    kind = @template.kind
    if kind == 'quote'
      ::Outsider::Erp::Prints::Document.quote(Current.account, real? ? real_report(kind, photos: false) : sample_report(kind), template: @template)
    elsif real?
      company, code = real_target
      reporter = ::Outsider::Erp::ServiceOrderReport.new(Current.account)
      ::Outsider::Erp::Prints::Document.for_service_order(Current.account, @template, reporter.build(company, code, photos: false), reporter)
    else
      report = sample_report(kind)
      ::Outsider::Erp::Prints::Document.new(@template, ::Outsider::Erp::Prints::Document.values(Current.account, kind, report),
                                            filename: ::Outsider::Erp::ServiceOrderPdf.new(report).filename)
    end
  end

  def summary(template)
    {
      id: template.id, kind: template.kind, name: template.name, builtin: template.builtin, updated_at: template.updated_at.to_i,
      theme: template.theme, block_types: template.blocks.pluck('type'),
      photos: template.blocks.any? { |block| block['type'] == 'checklist' && block['photos'] != 'without' }
    }
  end

  def full(template)
    summary(template).merge(
      content: template.content,
      images: template.images.attachments.to_h { |attachment| [attachment.id, file_path(attachment)] }
    )
  end

  def file_path(attachment)
    Rails.application.routes.url_helpers.rails_blob_path(attachment, only_path: true)
  end

  def data_uri(bytes)
    return unless bytes.is_a?(String) && bytes.b.start_with?("\xFF\xD8".b, "\x89PNG".b)

    "data:#{bytes.b.start_with?("\x89PNG".b) ? 'image/png' : 'image/jpeg'};base64,#{Base64.strict_encode64(bytes)}"
  end
end
