# OUTSIDER: agendar uma OS do ERP nas agendas conectadas de quem agenda (Microsoft e/ou Google) e avisar por WhatsApp
# (Outsider::Erp::OrderScheduler). Pede "Usa" na aba Ordens de serviço do perfil, como o envio do relatório.
#   GET    service_orders/schedule        a OS, o evento sugerido, as agendas, sugestões de convidados e os agendamentos
#   POST   service_orders/schedule        marcar (e avisar por WhatsApp, se escolheu contatos)
#   DELETE service_orders/schedule/:id    cancelar (só quem marcou)
#   POST   service_orders/message         só um texto pelo WhatsApp sobre a OS (até 5 contatos)
#   GET    service_orders/people          busca de contatos (e-mail/WhatsApp) e colegas (e-mail)
#   GET    service_orders/checklist       se o checklist da OS já chegou respondido (libera Emitir relatório e Enviar)
class Api::V1::Accounts::Outsider::Erp::OrderSchedulesController < Api::V1::Accounts::Outsider::Erp::BaseController
  MAX_PEOPLE = 15

  before_action :ensure_orders_enabled
  before_action :ensure_order_access

  rescue_from(::Outsider::Erp::Delivery::Blocked) do |error|
    render json: { error: 'send_blocked', reason: error.message }, status: :unprocessable_entity
  end
  rescue_from(::Outsider::Erp::Records::Detail::NotFound) { render json: { error: 'os_not_found' }, status: :not_found }

  def show
    company, number = target
    render json: scheduler.defaults(company, number)
  end

  def create
    company, number = target
    render json: scheduler.create(company, number, schedule_params), status: :created
  end

  def destroy
    schedule = ::Outsider::Erp::OrderSchedule.where(account_id: Current.account.id).find(params[:id])
    scheduler.cancel(schedule)
    head :no_content
  rescue ::Outsider::Erp::OrderCalendars::Error => e
    render json: { error: 'calendar', message: e.message.to_s.first(200) }, status: :bad_gateway
  end

  def message
    target
    sent = scheduler.message(params.permit(:inbox_id, :message, contact_ids: []))
    render json: { sent: sent }
  end

  def checklist
    company, number = target
    render json: { answered: ::Outsider::Erp::OrderChecklist.new(Current.account).answered?(company, number) }
  rescue ::Outsider::Erp::Client::Error
    render json: { answered: nil, error: 'erp_unavailable' }
  end

  # contatos (com telefone e/ou e-mail) e colegas da conta (só e-mail)
  def people
    query = params[:q].to_s.strip
    return render json: { contacts: [], users: [] } if query.size < 2

    contacts = ::Outsider::Erp::BudgetRecipients.new(Current.account_user).contacts(query)
    term = "%#{User.sanitize_sql_like(query)}%"
    users = Current.account.users.where('users.name ILIKE :term OR users.email ILIKE :term', term: term).order(:name).limit(MAX_PEOPLE)
    render json: { contacts: contacts, users: users.map { |user| { id: user.id, name: user.name, email: user.email } } }
  end

  private

  def scheduler
    @scheduler ||= ::Outsider::Erp::OrderScheduler.new(Current.account_user, time_zone: params[:time_zone])
  end

  def target
    company = params.require(:company).to_s
    number = Integer(params.require(:code).to_s, exception: false)
    raise ::Outsider::Erp::Records::Detail::NotFound unless number&.positive? && settings.companies.include?(company)

    [company, number]
  end

  def schedule_params
    params.permit(:title, :start, :end, :all_day, :location, :body, calendars: [], attendees: [],
                                                                    whatsapp: [:inbox_id, :message, { contact_ids: [] }])
  end

  def ensure_order_access
    render json: { error: 'erp_forbidden' }, status: :forbidden unless allows_screen?('erp_orders', 'use')
  end
end
