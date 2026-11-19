# OUTSIDER: módulo de orçamento de peças e serviços do ERP (Outsider::Erp::Budget), separado da proposta comercial do
# CRM. Aparece no painel do contato, na aba CRM da conversa e no negócio. Exige o acesso de uso da integração (tela
# "erp"); rascunho só muda quem criou ou um administrador; "Gravar no ERP" exige também a gravação de orçamento ligada
# nas Configurações e roda no Sidekiq (Outsider::Erp::BudgetSubmitJob), a tela acompanha pelo status.
# Orçamento feito no próprio Mais Prático: "import" cria o registro para enviar o PDF dele e guardar os envios.
# Desconto acima do limite das Configurações: "approve_discount" confere no ERP o código e a senha de quem pode liberar
# (Outsider::Erp::DiscountApprover); a senha não é guardada nem registrada ("password" é filtrado do log).
class Api::V1::Accounts::Outsider::Erp::BudgetsController < Api::V1::Accounts::Outsider::Erp::BaseController
  ITEM_FIELDS = %i[codigo descricao unidade tipo ncm quantidade preco desconto].freeze

  before_action :ensure_erp_use
  before_action :budget, except: [:index, :create, :import, :options]
  before_action :ensure_editable, only: [:update, :destroy, :submit, :approve_discount]

  rescue_from(ActiveRecord::RecordNotFound) { render json: { error: 'not_found' }, status: :not_found }
  rescue_from(::Outsider::Erp::QuoteReport::NotFound) { render json: { error: 'erp_quote_not_found' }, status: :not_found }
  rescue_from(::Outsider::Erp::BudgetForm::Invalid, ::Outsider::Erp::BudgetDefaults::Invalid, ::Outsider::Erp::BudgetImporter::Invalid,
              ArgumentError) do |error|
    render json: { error: 'invalid', reason: error.message }, status: :unprocessable_entity
  end
  rescue_from(::Outsider::Erp::BudgetSender::Blocked) do |error|
    render json: { error: 'send_blocked', reason: error.message }, status: :unprocessable_entity
  end
  rescue_from(::Outsider::Erp::DiscountApprover::Refused) do |error|
    render json: { error: 'approval_refused', reason: error.message }, status: :unprocessable_entity
  end

  # orçamentos deste contato no chat (rascunhos, gravados e os do ERP já enviados por aqui), mais novos primeiro
  def index
    list = budgets.where(contact_id: contact.id).includes(:user, :sends).order(updated_at: :desc).limit(50)
    render json: { budgets: list.map { |item| serializer.summary(item) }, can_create: can_create_quote? }
  end

  def show
    render json: { budget: serializer.full(@budget) }
  end

  def create
    created = defaults.build(contact: contact, conversation_id: params[:conversation_id], opportunity_id: params[:opportunity_id])
    render json: { budget: serializer.full(created) }, status: :created
  end

  # autosave do editor: cliente, condições e/ou itens (só o que veio)
  def update
    ::Outsider::Erp::BudgetForm.new(@budget, settings).apply(budget_params)
    render json: { budget: serializer.full(@budget) }
  end

  # rascunho que já tem número no ERP (gravação parou no meio) não some: o certo é gravar de novo
  def destroy
    return render json: { error: 'in_erp' }, status: :unprocessable_entity if @budget.in_erp?

    @budget.destroy!
    head :no_content
  end

  # "Gravar no ERP": vira "submitting" e o job grava; parado há mais de 3 min (job morreu), pode pedir de novo
  def submit
    return render json: { error: 'quote_write_disabled' }, status: :forbidden unless can_create_quote?
    if @budget.erp_number.blank? && discount_policy.blocked?
      return render json: { error: 'invalid', reason: 'desconto_sem_liberacao' }, status: :unprocessable_entity
    end

    @budget.update!(status: :submitting, erp_result: @budget.erp_result.except('error'))
    enqueue_submit
    render json: { budget: serializer.full(@budget) }
  end

  # PDF no modelo do relatório do Mais Prático: o oficial (do ERP) quando já gravado, senão a prévia do rascunho
  def pdf
    report = if @budget.in_erp?
               ::Outsider::Erp::QuoteReport.new(Current.account).build(@budget.company, @budget.erp_number)
             else
               ::Outsider::Erp::BudgetPreview.new(@budget).build
             end
    document = ::Outsider::Erp::QuotePdf.new(report)
    send_data document.render, filename: document.filename, type: 'application/pdf', disposition: 'inline'
  end

  # rascunho novo com o cliente, os itens e as condições deste (feito no chat ou no ERP)
  def copy
    copy = ::Outsider::Erp::BudgetCopy.new(Current.account).from(@budget)
    created = defaults.build(contact: contact, conversation_id: params[:conversation_id], opportunity_id: params[:opportunity_id], copy: copy)
    render json: { budget: serializer.full(created) }, status: :created
  end

  # registro de um orçamento feito no Mais Prático (espelho dos orçamentos), para PDF, envio e cópia
  def import
    record = ::Outsider::Erp::BudgetImporter.new(Current.account, Current.user)
                                            .import(company: params[:company], number: params[:number], contact: contact,
                                                    name: params[:name], conversation_id: params[:conversation_id])
    render json: { budget: serializer.full(record) }
  end

  # para a tela de envio: textos das Configurações já preenchidos, caixas de WhatsApp, contato e e-mails sugeridos
  def delivery
    return render json: { error: 'not_in_erp' }, status: :unprocessable_entity unless @budget.in_erp?

    report = ::Outsider::Erp::QuoteReport.new(Current.account).build(@budget.company, @budget.erp_number)
    render json: {
      texts: ::Outsider::Erp::BudgetTexts.new(settings, report, Current.user).as_json,
      filename: ::Outsider::Erp::QuotePdf.new(report).filename, total: report['total'], status: report['status'],
      recipients: recipients.defaults(@budget, report)
    }
  end

  # desconto acima do limite: código e senha de quem tem a permissão de desconto no ERP (ou é gerente). Vale para os
  # descontos que estão no rascunho agora
  def approve_discount
    return render json: { budget: serializer.full(@budget) } unless discount_policy.needs_approval?

    person = ::Outsider::Erp::DiscountApprover.new(Current.account_user).verify(@budget.company, params[:code], params[:password])
    discount_policy.grant(code: person[:code], name: person[:name], user: Current.user)
    render json: { budget: serializer.full(@budget) }
  end

  # outro contato para o WhatsApp (busca por nome ou telefone)
  def contacts
    render json: { contacts: recipients.contacts(params[:q]) }
  end

  def deliver
    ::Outsider::Erp::BudgetSender.new(Current.account_user).deliver(@budget, deliver_params)
    render json: { budget: serializer.full(@budget.reload) }
  end

  # listas do formulário: formas de pagamento, vendedores da unidade, gêneros e tipos de frete
  def options
    company = params.require(:company).to_s
    raise ArgumentError, 'company' unless settings.companies.include?(company)

    render json: {
      payment_terms: optional { ::Outsider::Erp::PaymentTerms.new(Current.account).list },
      sellers: optional { ::Outsider::Erp::Sellers.new(Current.account).list(company) },
      generos: ::Outsider::Erp::BudgetForm::GENEROS, fretes: ::Outsider::Erp::BudgetForm::FRETES,
      services_direct: settings.data['quote_services_direct'] == true, can_create: can_create_quote?,
      discount: ::Outsider::Erp::DiscountPolicy.limits(settings)
    }
  end

  private

  def budgets
    ::Outsider::Erp::Budget.where(account_id: Current.account.id)
  end

  def budget
    @budget ||= budgets.find(params[:id])
  end

  def serializer
    @serializer ||= ::Outsider::Erp::BudgetSerializer.new(Current.account_user, settings)
  end

  def discount_policy
    @discount_policy ||= ::Outsider::Erp::DiscountPolicy.new(@budget, settings)
  end

  def defaults
    ::Outsider::Erp::BudgetDefaults.new(Current.account, Current.user)
  end

  def recipients
    @recipients ||= ::Outsider::Erp::BudgetRecipients.new(Current.account_user)
  end

  def ensure_erp_use
    render json: { error: 'erp_forbidden' }, status: :forbidden unless can_use_erp?
  end

  # rascunho de quem criou ou de um administrador; "submit" também aceita a gravação parada no meio
  def ensure_editable
    return if serializer.editable?(budget)
    return if action_name == 'submit' && serializer.stuck?(budget) && (Current.account_user.administrator? || budget.user_id == Current.user.id)

    render json: { error: budget.draft? ? 'budget_forbidden' : 'not_draft' }, status: :forbidden
  end

  # lista que não carregou (ERP lento) vem vazia: o resto do formulário continua
  def optional
    yield
  rescue ::Outsider::Erp::Client::Error => e
    Rails.logger.warn("[Outsider::Erp] lista do orçamento: #{e.message}")
    []
  end

  def budget_params
    params.require(:budget).permit(:company, :customer_code, :customer_name, terms: ::Outsider::Erp::BudgetForm::TERMS.keys, items: ITEM_FIELDS)
  end

  def deliver_params
    params.permit(:channel, :contact_id, :inbox_id, :subject, :message, to: [])
  end

  # no dev a fila vai para o Redis da produção (outro código): grava na hora
  def enqueue_submit
    return ::Outsider::Erp::BudgetSubmitJob.perform_now(@budget.id, Current.user.id) if Rails.env.development?

    ::Outsider::Erp::BudgetSubmitJob.perform_later(@budget.id, Current.user.id)
  end
end
