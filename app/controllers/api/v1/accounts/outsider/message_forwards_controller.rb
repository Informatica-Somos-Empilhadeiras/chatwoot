# OUTSIDER: encaminhar mensagem (ver app/services/outsider/message_forward.rb).
class Api::V1::Accounts::Outsider::MessageForwardsController < Api::V1::Accounts::BaseController
  def create
    message = ::Outsider::MessageForward.new(
      account: Current.account, user: Current.user, inbox: target_inbox,
      contact: Current.account.contacts.find(params.require(:contact_id)),
      content: params[:content].presence, attachment_ids: params[:attachment_ids]
    ).perform
    render json: { conversation_id: message.conversation.display_id }
  rescue ::Outsider::MessageForward::NothingToForward
    render json: { error: 'nothing_to_forward' }, status: :unprocessable_entity
  rescue ::Outsider::MessageForward::MissingRecipient
    render json: { error: 'missing_recipient' }, status: :unprocessable_entity
  end

  private

  def target_inbox
    inbox = Current.account.inboxes.find(params.require(:inbox_id))
    authorize inbox, :show?
    inbox
  end
end
