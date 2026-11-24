# OUTSIDER: o envio de um PDF do ERP ao cliente pelas telas da OS e das notas fiscais (Outsider::Erp::DocumentSender):
# textos padrão das Configurações, para quem e por onde (delivery_payload) e o envio em si (deliver_document). O contato é
# o escolhido na tela, senão o da conversa de onde abriu, senão o vinculado ao cliente do ERP (client_code).
module Outsider::Erp::DocumentSending
  extend ActiveSupport::Concern

  included do
    rescue_from(::Outsider::Erp::Delivery::Blocked) do |error|
      render json: { error: 'send_blocked', reason: error.message }, status: :unprocessable_entity
    end
  end

  private

  # report: { 'numero', 'cliente' => { 'nome' } ... } para os textos; prefix: os textos das Configurações (os, nf)
  def delivery_payload(company, report, filename, prefix)
    source = conversation
    contact = delivery_contact(company, source)
    {
      texts: ::Outsider::Erp::BudgetTexts.new(settings, report, Current.user, prefix: prefix, contact_name: contact&.name).as_json,
      filename: filename,
      recipients: send_recipients.for_contact(contact, conversation_id: source&.id)
    }
  end

  # document: o que devolve { 'filename', 'content' } do PDF; label: "OS Nº 850", na nota do e-mail
  def deliver_document(document, label)
    ::Outsider::Erp::DocumentSender.new(Current.account_user).deliver(deliver_params, document: document, label: label, conversation: conversation)
  end

  def delivery_contact(company, source)
    return Current.account.contacts.find_by(id: params[:contact_id]) if params[:contact_id].present?
    return source.contact if source

    linked = ::Outsider::Erp::Records::ContactFinder.new(Current.account).for_clients([[company, params[:client_code]]]).values.first
    linked && Current.account.contacts.find_by(id: linked['contact_id'])
  end

  def send_recipients
    @send_recipients ||= ::Outsider::Erp::BudgetRecipients.new(Current.account_user)
  end

  def deliver_params
    params.permit(:channel, :contact_id, :inbox_id, :subject, :message, to: [], contact_ids: [])
  end

  def conversation
    return if params[:conversation_id].blank?

    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize conversation, :show?
    conversation
  end
end
