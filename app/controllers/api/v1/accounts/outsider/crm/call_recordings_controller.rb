# OUTSIDER: Telefonia > Gravações (Entrega 25): as ligações gravadas do mês, para ouvir, baixar e encaminhar a
# um contato (Outsider::Voice::RecordingForward). Cada pessoa vê o que Outsider::Voice::CallAccess deixa; apagar
# fica em CallsController#destroy_recording (só administrador).
class Api::V1::Accounts::Outsider::Crm::CallRecordingsController < Api::V1::Accounts::Outsider::Crm::BaseController
  PER_PAGE = 50

  before_action :fetch_call, only: [:forward_options, :forward]

  def index
    calls = recorded.includes(:user, :contact, recording_attachment: :blob).order(started_at: :desc)
    page = [params[:page].to_i, 1].max
    render json: { payload: calls.offset((page - 1) * PER_PAGE).limit(PER_PAGE).map { |call| call_json(call) },
                   meta: { page: page, per_page: PER_PAGE, total: calls.count, days: settings.recording_days,
                           bytes: recorded.joins(recording_attachment: :blob).sum('active_storage_blobs.byte_size') } }
  end

  # contatos sugeridos (ou a busca, com q) e as caixas para encaminhar
  def forward_options
    recipients = forwarder.recipients
    return render json: { contacts: recipients.contacts(params[:q]) } if params.key?(:q)

    render json: { contacts: recipients.contacts,
                   inboxes: { whatsapp: recipients.whatsapp_inboxes.map { |inbox| recipients.inbox_row(inbox) },
                              email: recipients.email_inboxes.map { |inbox| recipients.inbox_row(inbox) } } }
  end

  def forward
    conversation = forwarder.deliver(params.permit(:channel, :contact_id, :inbox_id, :message))
    render json: { conversation_id: conversation.display_id }, status: :created
  rescue ::Outsider::Voice::RecordingForward::Blocked => e
    render json: { error: e.message, message: I18n.t("outsider_voice.recording_forward.errors.#{e.message}") }, status: :unprocessable_entity
  end

  private

  def settings
    @settings ||= ::Outsider::Voice::Settings.new(Current.account)
  end

  def visible
    ::Outsider::Voice::CallAccess.new(crm_access, settings).scope(::Outsider::Voice::Call.where(account_id: Current.account.id))
  end

  def recorded
    scope = visible.where(id: ActiveStorage::Attachment.where(record_type: ::Outsider::Voice::Call.name, name: 'recording').select(:record_id))
    scope = scope.where(started_at: month_range)
    scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
    search(scope)
  end

  # nome do contato ou parte do número
  def search(scope)
    term = params[:q].to_s.strip
    return scope if term.empty?

    digits = term.delete('^0-9')
    contacts = Current.account.contacts.where('name ILIKE ?', "%#{Contact.sanitize_sql_like(term)}%").select(:id)
    found = scope.where(contact_id: contacts)
    digits.length >= 3 ? found.or(scope.where('from_number LIKE :d OR to_number LIKE :d', d: "%#{digits}%")) : found
  end

  def month_range
    month = ::Outsider::Crm::MonthlyConfig.month(params[:month])
    Date.strptime(month, '%Y-%m').in_time_zone(settings.time_zone).all_month
  end

  def fetch_call
    @call = visible.find_by(id: params[:id])
    head :not_found unless @call&.recording&.attached?
  end

  def forwarder
    ::Outsider::Voice::RecordingForward.new(Current.account_user, @call)
  end

  def call_json(call)
    blob = call.recording.blob
    call.slice(:id, :direction, :status, :started_at, :talk_seconds, :contact_id).merge(
      customer_number: call.customer_number, contact_name: call.contact&.name, user: ::Outsider::Crm::Serializer.user(call.user),
      recording_url: rails_blob_path(call.recording, only_path: true), byte_size: blob.byte_size,
      expires_on: (call.started_at.in_time_zone(settings.time_zone) + settings.recording_days.days).to_date
    )
  end
end
