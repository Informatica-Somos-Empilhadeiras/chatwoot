# OUTSIDER: aba Ligações do negócio (Entrega 26): as ligações vinculadas a ele, com a gravação e o recado para
# ouvir ali mesmo. Quem enxerga o negócio vê as ligações dele, de qualquer vendedor (a regra das telas da
# Telefonia, Outsider::Voice::CallAccess, vale para as listas de lá).
class Api::V1::Accounts::Outsider::Crm::OpportunityCallsController < Api::V1::Accounts::Outsider::Crm::OpportunityChildController
  LIMIT = 100

  def index
    calls = ::Outsider::Voice::Call.where(account_id: Current.account.id, opportunity_id: @opportunity.id).external
                                   .includes(:user, recording_attachment: :blob, voicemail_attachment: :blob)
                                   .order(started_at: :desc).limit(LIMIT)
    render json: { payload: calls.map { |call| call_json(call) } }
  end

  private

  def call_json(call)
    call.slice(:id, :direction, :status, :started_at, :answered_at, :ended_at, :talk_seconds).merge(
      customer_number: call.customer_number, user: ::Outsider::Crm::Serializer.user(call.user), ivr: call.ivr_summary,
      recording_url: call.recording.attached? ? rails_blob_path(call.recording, only_path: true) : nil,
      voicemail_url: call.voicemail.attached? ? rails_blob_path(call.voicemail, only_path: true) : nil
    )
  end
end
