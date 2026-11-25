# OUTSIDER: OS do ERP feita no chat (Outsider::Erp::OrderDraft): a Nova OS (conversa e contato) e "Converter em OS" no
# painel de um orçamento do ERP. Exige a linha do perfil de acesso (erp_order_create / erp_quote_convert, "Usa") e a
# função ligada nas Configurações, na unidade liberada. "Gravar no ERP" roda no Sidekiq (Outsider::Erp::OrderSubmitJob) e
# a tela acompanha pelo status. "preview" faz só a conferência da conversão (nada é gravado). "cancel_os" muda a OS
# gravada pelo chat para CANCELADA pelas rotas oficiais (nada é apagado).
class Api::V1::Accounts::Outsider::Erp::OrderDraftsController < Api::V1::Accounts::Outsider::Erp::BaseController
  ITEM_FIELDS = ::Outsider::Erp::Orders::Form::ITEM_FIELDS.map(&:to_sym).freeze

  before_action :draft, only: [:show, :update, :destroy, :submit, :cancel_os]
  before_action :ensure_kind_access
  before_action :ensure_editable, only: [:update, :destroy]

  rescue_from(ActiveRecord::RecordNotFound) { render json: { error: 'not_found' }, status: :not_found }
  rescue_from(::Outsider::Erp::Orders::Form::Invalid, ::Outsider::Erp::Orders::Canceller::Invalid, ArgumentError) do |error|
    render json: { error: 'invalid', reason: error.message }, status: :unprocessable_entity
  end

  # rascunhos e OS gravadas pelo chat deste contato (ou deste orçamento), mais novos primeiro
  def index
    list = drafts.includes(:user).order(updated_at: :desc).limit(30)
    list = if params[:quote_number].present?
             list.where(company: params[:company].to_s,
                        quote_number: params[:quote_number].to_i)
           else
             list.where(contact_id: contact.id)
           end
    render json: { drafts: list.map { |item| serializer.summary(item) }, can_create: can_create_order?, can_convert: can_convert_quote? }
  end

  def show
    render json: { draft: serializer.full(@draft) }
  end

  # Nova OS: cliente do vínculo do contato (na primeira unidade liberada que ele tiver); conversão: a do orçamento, uma
  # por orçamento (o rascunho aberto ou a OS já gravada voltam em vez de criar outro)
  def create
    created = kind == 'conversion' ? conversion_draft : fresh_draft
    render json: { draft: serializer.full(created) }, status: :created
  end

  def update
    ::Outsider::Erp::Orders::Form.new(@draft, settings).apply(draft_params)
    render json: { draft: serializer.full(@draft) }
  end

  # rascunho que já tem número no ERP (gravação parou no meio) não some: o certo é gravar de novo
  def destroy
    return render json: { error: 'in_erp' }, status: :unprocessable_entity if @draft.in_erp?

    @draft.destroy!
    head :no_content
  end

  # "Gravar no ERP": vira "submitting" e o job grava; parado há mais de 3 min (job morreu), pode pedir de novo
  def submit
    return render json: { error: 'order_forbidden' }, status: :forbidden unless serializer.submittable?(@draft)

    @draft.update!(status: :submitting, erp_result: @draft.erp_result.to_h.except('error'))
    enqueue_submit
    render json: { draft: serializer.full(@draft) }
  end

  def cancel_os
    return render json: { error: 'order_forbidden' }, status: :forbidden unless serializer.owner?(@draft)

    ::Outsider::Erp::Orders::Canceller.new(@draft, user: Current.user).call
    render json: { draft: serializer.full(@draft.reload) }
  end

  # listas do formulário (tipos, técnicos, classes, máquina obrigatória, quem grava)
  def options
    render json: order_options.form(params.require(:company).to_s)
  end

  # máquinas do cliente (cadastro + contratos ativos); com q, qualquer máquina da unidade
  def machines
    render json: { machines: order_options.machines(params.require(:company).to_s, params[:customer], params[:q]) }
  end

  # conversão: a conferência que a tela mostra antes de converter (só leitura)
  def preview
    company = params.require(:company).to_s
    raise ArgumentError, 'company' unless settings.order_company?(company)

    probe = drafts.new(company: company, kind: :conversion, quote_number: params.require(:quote_number).to_i, user: Current.user)
    render json: ::Outsider::Erp::Orders::Preview.new(probe, user: Current.user).call
  end

  private

  def drafts = ::Outsider::Erp::OrderDraft.where(account_id: Current.account.id)

  def draft = @draft ||= drafts.find(params[:id])

  def kind
    return @draft.kind if @draft

    %w[conversion preview].include?(params[:kind].to_s) || action_name == 'preview' ? 'conversion' : 'fresh'
  end

  def serializer = @serializer ||= ::Outsider::Erp::Orders::Serializer.new(Current.account_user)

  def order_options = ::Outsider::Erp::Orders::Options.new(Current.account, Current.user)

  # a linha do perfil e a função ligada: Nova OS pede erp_order_create, conversão erp_quote_convert. A lista só pede
  # uma das duas (cada tela mostra o que pode)
  def ensure_kind_access
    allowed = if action_name == 'index'
                can_create_order? || can_convert_quote?
              else
                kind == 'conversion' ? can_convert_quote? : can_create_order?
              end
    render json: { error: 'order_forbidden' }, status: :forbidden unless allowed
  end

  def ensure_editable
    render json: { error: 'not_draft' }, status: :forbidden unless serializer.editable?(@draft)
  end

  def fresh_draft
    link = optional_contact && ::Outsider::Erp::ContactLink.new(optional_contact).links.find { |row| settings.order_company?(row['empresa']) }
    company = link&.dig('empresa') || params[:company].presence || settings.order_companies.first
    raise ArgumentError, 'company' unless settings.order_company?(company)

    drafts.create!(user: Current.user, contact: optional_contact, conversation_id: conversation_id, kind: :fresh, status: :draft,
                   company: company, customer_code: link&.dig('codigo'), customer_name: link&.dig('nome'),
                   fields: { 'classe' => nil, 'enviar_app' => false, 'agendar' => false, 'maquina_do_cliente' => true })
  end

  def conversion_draft
    company = params.require(:company).to_s
    raise ArgumentError, 'company' unless settings.order_company?(company)

    number = params.require(:quote_number).to_i
    raise ArgumentError, 'quote_number' unless number.positive?

    existing = drafts.where(company: company, quote_number: number, kind: :conversion).order(:id)
    existing.find(&:created?) || existing.find { |item| !item.created? } ||
      drafts.create!(user: Current.user, contact: optional_contact, conversation_id: conversation_id, kind: :conversion, status: :draft,
                     company: company, quote_number: number, customer_code: params[:customer_code].presence,
                     customer_name: params[:customer_name].to_s.squish.first(150).presence,
                     fields: { 'enviar_app' => false, 'agendar' => false, 'maquina_do_cliente' => true })
  end

  def optional_contact
    return @optional_contact if defined?(@optional_contact)

    @optional_contact = params[:contact_id].present? ? contact : nil
  end

  def conversation_id
    ::Outsider::Erp::Budget.conversation_id_for(optional_contact, params[:conversation_id])
  end

  def draft_params
    params.require(:draft).permit(:company, :customer_code, :customer_name, fields: ::Outsider::Erp::Orders::Form::FIELDS.keys,
                                                                            items: ITEM_FIELDS)
  end

  # no dev a fila vai para o Redis da produção (outro código): grava na hora
  def enqueue_submit
    return ::Outsider::Erp::OrderSubmitJob.perform_now(@draft.id, Current.user.id) if Rails.env.development?

    ::Outsider::Erp::OrderSubmitJob.perform_later(@draft.id, Current.user.id)
  end
end
